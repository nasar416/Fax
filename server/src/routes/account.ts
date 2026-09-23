import type { AccountRow, Env } from "../env";
import { balanceOf, publicAccount, registerToken, requireAccount } from "../accounts";
import { verifyAppleIdentityToken, sha256Hex } from "../crypto";
import { HttpError, json, now, readJson, type Router } from "../http";
import { releaseNumber } from "../telnyx";

async function numbersOf(env: Env, accountId: string) {
  const { results } = await env.DB.prepare("SELECT e164, label, release_after FROM numbers WHERE account_id = ? ORDER BY created_at").bind(accountId).all<{ e164: string; label: string; release_after: number | null }>();
  return results;
}

export function accountRoutes(router: Router, env: Env) {
  /** First launch (and every launch): register the device's account token. */
  router.on("POST", "/v1/accounts", async (request) => {
    const body = await readJson<{ token?: string }>(request);
    if (!body.token || !/^[0-9a-fA-F-]{36}$/.test(body.token)) throw new HttpError(400, "invalid_token");
    const account = await registerToken(env, body.token);
    return json(publicAccount(account, await numbersOf(env, account.id)));
  });

  router.on("GET", "/v1/me", async (request) => {
    const account = await requireAccount(request, env);
    return json(publicAccount(account, await numbersOf(env, account.id)));
  });

  router.on("PATCH", "/v1/me", async (request) => {
    const account = await requireAccount(request, env);
    const body = await readJson<{ retentionDays?: number; pausedUntil?: number | null; shareUsage?: boolean; sendingNumber?: string }>(request);
    const days = body.retentionDays;
    if (days !== undefined && ![7, 30, 90, 365].includes(days)) throw new HttpError(400, "invalid_retention");
    if (body.sendingNumber) {
      const owns = await env.DB.prepare("SELECT 1 FROM numbers WHERE e164 = ? AND account_id = ?").bind(body.sendingNumber, account.id).first();
      if (!owns) throw new HttpError(400, "not_your_number");
    }
    await env.DB.prepare(
      `UPDATE accounts SET retention_days = COALESCE(?, retention_days), paused_until = ?, share_usage = COALESCE(?, share_usage),
       sending_number = COALESCE(?, sending_number) WHERE id = ?`,
    ).bind(days ?? null, body.pausedUntil === undefined ? account.paused_until : body.pausedUntil,
      body.shareUsage === undefined ? null : body.shareUsage ? 1 : 0, body.sendingNumber ?? null, account.id).run();
    const updated = (await env.DB.prepare("SELECT * FROM accounts WHERE id = ?").bind(account.id).first<AccountRow>())!;
    return json(publicAccount(updated, await numbersOf(env, account.id)));
  });

  /**
   * Sign in with Apple. If this Apple ID already has an account (another iPhone),
   * this device joins that account; otherwise the guest account becomes permanent.
   */
  router.on("POST", "/v1/auth/apple", async (request) => {
    const account = await requireAccount(request, env);
    const body = await readJson<{ identityToken?: string }>(request);
    if (!body.identityToken) throw new HttpError(400, "missing_identity_token");
    let sub: string;
    try {
      ({ sub } = await verifyAppleIdentityToken(body.identityToken, env.BUNDLE_ID));
    } catch (err) {
      throw new HttpError(401, "invalid_identity_token", (err as Error).message);
    }
    const owner = await env.DB.prepare("SELECT * FROM accounts WHERE apple_sub = ?").bind(sub).first<AccountRow>();
    if (!owner) {
      await env.DB.prepare("UPDATE accounts SET apple_sub = ? WHERE id = ?").bind(sub, account.id).run();
    } else if (owner.id !== account.id) {
      // Move this device's token to the existing account. Keep the guest account only if it has data.
      const token = (request.headers.get("authorization") ?? "").slice(7).trim().toLowerCase();
      await env.DB.prepare("UPDATE tokens SET account_id = ? WHERE token_hash = ?").bind(owner.id, await sha256Hex(token)).run();
      const guest = balanceOf(account);
      if (!guest.plan) await env.DB.prepare("DELETE FROM accounts WHERE id = ? AND apple_sub IS NULL").bind(account.id).run();
    }
    const current = (await env.DB.prepare("SELECT * FROM accounts WHERE id = ?").bind(owner?.id ?? account.id).first<AccountRow>())!;
    return json(publicAccount(current, await numbersOf(env, current.id)));
  });

  /** Deletes everything: faxes, files, numbers, the account. Required by App Review. */
  router.on("DELETE", "/v1/me", async (request) => {
    const account = await requireAccount(request, env);
    for (const n of await numbersOf(env, account.id)) {
      try { await releaseNumber(env, n.e164); } catch (err) { console.error("release failed", n.e164, err); }
    }
    const { results } = await env.DB.prepare("SELECT r2_key FROM faxes WHERE account_id = ? AND r2_key IS NOT NULL").bind(account.id).all<{ r2_key: string }>();
    for (let i = 0; i < results.length; i += 500) {
      await env.FAXES.delete(results.slice(i, i + 500).map((r) => r.r2_key));
    }
    await env.DB.batch([
      env.DB.prepare("DELETE FROM faxes WHERE account_id = ?").bind(account.id),
      env.DB.prepare("DELETE FROM numbers WHERE account_id = ?").bind(account.id),
      env.DB.prepare("DELETE FROM blocked WHERE account_id = ?").bind(account.id),
      env.DB.prepare("DELETE FROM tokens WHERE account_id = ?").bind(account.id),
      env.DB.prepare("DELETE FROM accounts WHERE id = ?").bind(account.id),
    ]);
    return json({ deleted: true, at: now() });
  });
}
