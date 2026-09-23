import type { Env, FaxRow } from "../env";
import { requireAccount } from "../accounts";
import { verifyMediaSignature } from "../crypto";
import { HttpError, json, now, readJson, type Router } from "../http";
import { numbersIncluded, type Plan } from "../plans";
import { toE164 } from "../phone";
import { orderNumber, searchNumbers } from "../telnyx";

const DEFAULT_CONFIG = {
  minimumVersion: "1.0.0",
  maintenance: false,
  maintenanceBackAround: null as string | null,
  announcement: null as string | null,
  supportEmail: "developer.nasar416@gmail.com",
  teamEnabled: true,
  iCloudBackupEnabled: true,
};

export function miscRoutes(router: Router, env: Env) {
  /** Remote config for the app. Change rows in the `config` table; no App Store update needed. */
  router.on("GET", "/v1/config", async () => {
    const { results } = await env.DB.prepare("SELECT key, value FROM config").all<{ key: string; value: string }>();
    const config: Record<string, unknown> = { ...DEFAULT_CONFIG };
    for (const row of results) {
      try { config[row.key] = JSON.parse(row.value); } catch { config[row.key] = row.value; }
    }
    return json(config, 200, { "cache-control": "public, max-age=300" });
  });

  /** Telnyx fetches outgoing PDFs here with a signed, expiring link. */
  router.on("GET", "/v1/media/:id", async (request, { id }) => {
    const url = new URL(request.url);
    if (!(await verifyMediaSignature(env.MEDIA_SIGNING_SECRET, id!, url.searchParams.get("exp"), url.searchParams.get("sig")))) {
      throw new HttpError(403, "bad_signature");
    }
    const fax = await env.DB.prepare("SELECT * FROM faxes WHERE id = ? AND direction = 'sent'").bind(id).first<FaxRow>();
    const object = fax?.r2_key ? await env.FAXES.get(fax.r2_key) : null;
    if (!object) throw new HttpError(404, "not_found");
    return new Response(object.body, { headers: { "content-type": "application/pdf" } });
  });

  router.on("GET", "/v1/blocked", async (request) => {
    const account = await requireAccount(request, env);
    const { results } = await env.DB.prepare("SELECT e164 AS number, reason, created_at AS blockedAt FROM blocked WHERE account_id = ? ORDER BY created_at DESC")
      .bind(account.id).all();
    return json({ blocked: results });
  });

  router.on("POST", "/v1/blocked", async (request) => {
    const account = await requireAccount(request, env);
    const body = await readJson<{ number?: string; reason?: string }>(request);
    const e164 = toE164(body.number ?? "");
    if (!e164) throw new HttpError(400, "invalid_number");
    await env.DB.prepare("INSERT OR IGNORE INTO blocked (account_id, e164, reason, created_at) VALUES (?, ?, ?, ?)")
      .bind(account.id, e164, (body.reason ?? "").slice(0, 80), now()).run();
    return json({ number: e164 }, 201);
  });

  router.on("DELETE", "/v1/blocked/:number", async (request, { number }) => {
    const account = await requireAccount(request, env);
    await env.DB.prepare("DELETE FROM blocked WHERE account_id = ? AND e164 = ?").bind(account.id, toE164(number!) ?? number).run();
    return json({ ok: true });
  });

  /** Numbers a paying user can pick from. */
  router.on("GET", "/v1/numbers/available", async (request) => {
    const account = await requireAccount(request, env);
    if (!account.plan) throw new HttpError(402, "plan_required", "Choose a plan to get your own fax number.");
    const url = new URL(request.url);
    const country = (url.searchParams.get("country") ?? "US").toUpperCase().slice(0, 2);
    const area = url.searchParams.get("areaCode")?.replace(/\D/g, "").slice(0, 4) || undefined;
    const numbers = await searchNumbers(env, country, area);
    return json({ numbers: numbers.map((n) => ({ number: n.phone_number, region: n.region_information?.[0]?.region_name ?? null })) });
  });

  router.on("POST", "/v1/numbers", async (request) => {
    const account = await requireAccount(request, env);
    if (!account.plan) throw new HttpError(402, "plan_required", "Choose a plan to get your own fax number.");
    const body = await readJson<{ number?: string; label?: string }>(request);
    const e164 = toE164(body.number ?? "");
    if (!e164) throw new HttpError(400, "invalid_number");
    const count = await env.DB.prepare("SELECT COUNT(*) AS n FROM numbers WHERE account_id = ?").bind(account.id).first<{ n: number }>();
    if ((count?.n ?? 0) >= numbersIncluded(account.plan as Plan)) {
      throw new HttpError(402, "number_limit", "Your plan’s numbers are all in use. Upgrade to add another.");
    }
    const orderId = await orderNumber(env, e164);
    await env.DB.prepare("INSERT INTO numbers (e164, account_id, label, telnyx_order_id, created_at) VALUES (?, ?, ?, ?, ?)")
      .bind(e164, account.id, (body.label ?? "").slice(0, 40), orderId, now()).run();
    if (!account.sending_number) await env.DB.prepare("UPDATE accounts SET sending_number = ? WHERE id = ?").bind(e164, account.id).run();
    return json({ number: e164 }, 201);
  });
}
