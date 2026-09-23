import type { AccountRow, Env } from "./env";
import { sha256Hex, randomId } from "./crypto";
import { HttpError, now } from "./http";
import { cycleSeconds, pageLimit, pagesLeft, splitCharge, type Charge, type Period, type Plan } from "./plans";

/** The app sends its account token (a random UUID kept in the Keychain) as a bearer token. */
export async function requireAccount(request: Request, env: Env): Promise<AccountRow> {
  const header = request.headers.get("authorization") ?? "";
  const token = header.startsWith("Bearer ") ? header.slice(7).trim() : "";
  if (!/^[0-9a-fA-F-]{36}$/.test(token)) throw new HttpError(401, "unauthorized", "Missing or invalid account token.");
  const row = await env.DB.prepare(
    "SELECT a.* FROM tokens t JOIN accounts a ON a.id = t.account_id WHERE t.token_hash = ?",
  ).bind(await sha256Hex(token.toLowerCase())).first<AccountRow>();
  if (!row) throw new HttpError(401, "unknown_account", "Register this device first.");
  return row;
}

/** Creates a guest account for a new token, or returns the existing one. */
export async function registerToken(env: Env, token: string): Promise<AccountRow> {
  const hash = await sha256Hex(token.toLowerCase());
  const existing = await env.DB.prepare(
    "SELECT a.* FROM tokens t JOIN accounts a ON a.id = t.account_id WHERE t.token_hash = ?",
  ).bind(hash).first<AccountRow>();
  if (existing) return existing;
  const id = randomId();
  const ts = now();
  await env.DB.batch([
    env.DB.prepare("INSERT INTO accounts (id, created_at, cycle_start) VALUES (?, ?, ?)").bind(id, ts, ts),
    env.DB.prepare("INSERT INTO tokens (token_hash, account_id, created_at) VALUES (?, ?, ?)").bind(hash, id, ts),
  ]);
  return (await env.DB.prepare("SELECT * FROM accounts WHERE id = ?").bind(id).first<AccountRow>())!;
}

export function balanceOf(a: AccountRow) {
  return {
    plan: (a.plan as Plan | null) ?? null,
    period: (a.period as Period | null) ?? null,
    pagesUsed: a.pages_used,
    extraPages: a.extra_pages,
    freePagesLeft: a.free_pages_left,
  };
}

export function publicAccount(a: AccountRow, numbers: { e164: string; label: string }[]) {
  const b = balanceOf(a);
  return {
    id: a.id,
    signedIn: !!a.apple_sub,
    plan: b.plan,
    period: b.period,
    planExpiresAt: a.plan_expires_at,
    pageLimit: b.plan && b.period ? pageLimit(b.plan, b.period) : 3,
    pagesUsed: a.pages_used,
    pagesLeft: pagesLeft(b),
    extraPages: a.extra_pages,
    cycleResetsAt: a.cycle_start + cycleSeconds(b.period),
    retentionDays: a.retention_days,
    pausedUntil: a.paused_until,
    shareUsage: !!a.share_usage,
    sendingNumber: a.sending_number ?? numbers[0]?.e164 ?? null,
    numbers,
  };
}

/**
 * Charges pages atomically. The UPDATE only succeeds if the balance is still what we read,
 * so two faxes sent at the same moment can't both spend the same pages.
 */
export async function charge(env: Env, accountId: string, cost: number): Promise<Charge | null> {
  for (let attempt = 0; attempt < 3; attempt++) {
    const a = await env.DB.prepare("SELECT * FROM accounts WHERE id = ?").bind(accountId).first<AccountRow>();
    if (!a) return null;
    const split = splitCharge(balanceOf(a), cost);
    if (!split) return null;
    const res = await env.DB.prepare(
      `UPDATE accounts SET pages_used = pages_used + ?, extra_pages = extra_pages - ?, free_pages_left = free_pages_left - ?
       WHERE id = ? AND pages_used = ? AND extra_pages = ? AND free_pages_left = ?`,
    ).bind(split.fromPlan, split.fromExtra, split.fromFree, accountId, a.pages_used, a.extra_pages, a.free_pages_left).run();
    if (res.meta.changes === 1) return split;
  }
  throw new HttpError(409, "busy", "Please try again.");
}

/** Gives pages back (failed fax, or the real page count was lower). */
export async function refund(env: Env, accountId: string, c: Charge): Promise<void> {
  if (c.fromPlan + c.fromExtra + c.fromFree === 0) return;
  await env.DB.prepare(
    `UPDATE accounts SET pages_used = MAX(pages_used - ?, 0), extra_pages = extra_pages + ?, free_pages_left = free_pages_left + ? WHERE id = ?`,
  ).bind(c.fromPlan, c.fromExtra, c.fromFree, accountId).run();
}
