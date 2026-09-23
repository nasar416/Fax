import type { AccountRow, Env, FaxRow } from "../env";
import { charge, refund, requireAccount } from "../accounts";
import { randomId, signedMediaUrl } from "../crypto";
import { HttpError, json, now, readJson, type Router } from "../http";
import { isAllowedCountry, isBlockedDestination, pageMultiplier, toE164 } from "../phone";
import { sendFax } from "../telnyx";

const MAX_PDF_BYTES = 20 * 1024 * 1024;
const MAX_PAGES = 50;
const MAX_FAXES_PER_DAY = 50;

export function publicFax(f: FaxRow) {
  return {
    id: f.id,
    direction: f.direction,
    number: f.party_number,
    ownNumber: f.own_number,
    pages: f.pages,
    cost: f.cost,
    state: f.state,
    failureReason: f.failure_reason,
    unread: !!f.unread,
    createdAt: f.created_at,
    updatedAt: f.updated_at,
    deletedAt: f.deleted_at,
  };
}

async function loadFax(env: Env, account: AccountRow, id: string): Promise<FaxRow> {
  const fax = await env.DB.prepare("SELECT * FROM faxes WHERE id = ? AND account_id = ?").bind(id, account.id).first<FaxRow>();
  if (!fax) throw new HttpError(404, "fax_not_found");
  return fax;
}

export function faxRoutes(router: Router, env: Env) {
  router.on("GET", "/v1/faxes", async (request) => {
    const account = await requireAccount(request, env);
    const folder = new URL(request.url).searchParams.get("folder") ?? "inbox";
    const where: Record<string, string> = {
      inbox: "direction = 'received' AND deleted_at IS NULL",
      sent: "direction = 'sent' AND state IN ('delivered','failed') AND deleted_at IS NULL",
      outbox: "direction = 'sent' AND state IN ('queued','sending') AND deleted_at IS NULL",
      trash: "deleted_at IS NOT NULL",
    };
    const clause = where[folder];
    if (!clause) throw new HttpError(400, "invalid_folder");
    const { results } = await env.DB.prepare(`SELECT * FROM faxes WHERE account_id = ? AND ${clause} ORDER BY created_at DESC LIMIT 200`)
      .bind(account.id).all<FaxRow>();
    return json({ faxes: results.map(publicFax) });
  });

  /**
   * Sends a fax. multipart/form-data with:
   *   to     – the fax number
   *   pages  – page count of the PDF (the real count from Telnyx corrects it later)
   *   file   – one PDF with every page, cover sheet first
   */
  router.on("POST", "/v1/faxes", async (request) => {
    const account = await requireAccount(request, env);
    const form = await request.formData().catch(() => { throw new HttpError(400, "invalid_form"); });
    const to = toE164(String(form.get("to") ?? ""));
    const pages = Number(form.get("pages") ?? 0);
    const file: unknown = form.get("file");
    if (!to) throw new HttpError(400, "invalid_number", "That doesn’t look like a fax number.");
    if (!isAllowedCountry(to, env.ALLOWED_DIAL_CODES) || isBlockedDestination(to)) {
      throw new HttpError(400, "destination_not_supported", "Faxlane can’t send faxes to this number.");
    }
    if (!Number.isInteger(pages) || pages < 1 || pages > MAX_PAGES) throw new HttpError(400, "invalid_page_count");
    if (!(file instanceof File) || file.type !== "application/pdf") throw new HttpError(400, "pdf_required", "Attach one PDF.");
    if (file.size > MAX_PDF_BYTES) throw new HttpError(413, "file_too_large", "The PDF is larger than 20 MB.");

    const since = now() - 86400;
    const sentToday = await env.DB.prepare("SELECT COUNT(*) AS n FROM faxes WHERE account_id = ? AND direction = 'sent' AND created_at > ?")
      .bind(account.id, since).first<{ n: number }>();
    if ((sentToday?.n ?? 0) >= MAX_FAXES_PER_DAY) throw new HttpError(429, "daily_limit", "You’ve reached today’s sending limit.");

    const cost = pages * pageMultiplier(to);
    const paid = await charge(env, account.id, cost);
    if (!paid) throw new HttpError(402, "not_enough_pages", "You don’t have enough pages left.");

    const id = randomId();
    const key = `out/${account.id}/${id}.pdf`;
    const from = account.plan
      ? account.sending_number ?? (await env.DB.prepare("SELECT e164 FROM numbers WHERE account_id = ? ORDER BY created_at LIMIT 1").bind(account.id).first<{ e164: string }>())?.e164 ?? env.SHARED_FROM_NUMBER
      : env.SHARED_FROM_NUMBER;
    const ts = now();
    await env.FAXES.put(key, await file.arrayBuffer(), { httpMetadata: { contentType: "application/pdf" } });
    await env.DB.prepare(
      `INSERT INTO faxes (id, account_id, direction, party_number, own_number, pages, cost, charge_plan, charge_extra, charge_free, state, r2_key, created_at, updated_at)
       VALUES (?, ?, 'sent', ?, ?, ?, ?, ?, ?, ?, 'queued', ?, ?, ?)`,
    ).bind(id, account.id, to, from, pages, cost, paid.fromPlan, paid.fromExtra, paid.fromFree, key, ts, ts).run();

    try {
      const telnyxId = await sendFax(env, { to, from, mediaUrl: await signedMediaUrl(env.PUBLIC_BASE_URL, env.MEDIA_SIGNING_SECRET, id) });
      await env.DB.prepare("UPDATE faxes SET telnyx_fax_id = ?, updated_at = ? WHERE id = ?").bind(telnyxId, now(), id).run();
    } catch (err) {
      await refund(env, account.id, paid);
      await env.DB.prepare("UPDATE faxes SET state = 'failed', cost = 0, failure_reason = ?, updated_at = ? WHERE id = ?")
        .bind("The fax network is not available right now.", now(), id).run();
      throw err;
    }
    const fax = (await env.DB.prepare("SELECT * FROM faxes WHERE id = ?").bind(id).first<FaxRow>())!;
    return json(publicFax(fax), 201);
  });

  router.on("GET", "/v1/faxes/:id", async (request, { id }) => {
    const account = await requireAccount(request, env);
    return json(publicFax(await loadFax(env, account, id!)));
  });

  /** The PDF itself. Locked faxes stay closed until pages are added. */
  router.on("GET", "/v1/faxes/:id/pdf", async (request, { id }) => {
    const account = await requireAccount(request, env);
    const fax = await loadFax(env, account, id!);
    if (fax.state === "locked") throw new HttpError(402, "fax_locked", "Add pages to open this fax.");
    if (!fax.r2_key) throw new HttpError(404, "no_file");
    const object = await env.FAXES.get(fax.r2_key);
    if (!object) throw new HttpError(404, "file_expired", "This fax was removed after your retention period.");
    return new Response(object.body, { headers: { "content-type": "application/pdf", "cache-control": "private, no-store" } });
  });

  router.on("PATCH", "/v1/faxes/:id", async (request, { id }) => {
    const account = await requireAccount(request, env);
    const fax = await loadFax(env, account, id!);
    const body = await readJson<{ read?: boolean; deleted?: boolean }>(request);
    await env.DB.prepare("UPDATE faxes SET unread = ?, deleted_at = ?, updated_at = ? WHERE id = ?").bind(
      body.read === undefined ? fax.unread : body.read ? 0 : 1,
      body.deleted === undefined ? fax.deleted_at : body.deleted ? now() : null,
      now(), fax.id,
    ).run();
    return json(publicFax(await loadFax(env, account, fax.id)));
  });

  /** Opens a locked fax by charging its pages now. */
  router.on("POST", "/v1/faxes/:id/unlock", async (request, { id }) => {
    const account = await requireAccount(request, env);
    const fax = await loadFax(env, account, id!);
    if (fax.state !== "locked") return json(publicFax(fax));
    const paid = await charge(env, account.id, fax.pages);
    if (!paid) throw new HttpError(402, "not_enough_pages", "You don’t have enough pages left.");
    await env.DB.prepare("UPDATE faxes SET state = 'received', cost = ?, charge_plan = ?, charge_extra = ?, charge_free = ?, updated_at = ? WHERE id = ?")
      .bind(fax.pages, paid.fromPlan, paid.fromExtra, paid.fromFree, now(), fax.id).run();
    return json(publicFax(await loadFax(env, account, fax.id)));
  });

  /** Empties Trash for good. */
  router.on("DELETE", "/v1/trash", async (request) => {
    const account = await requireAccount(request, env);
    const { results } = await env.DB.prepare("SELECT id, r2_key FROM faxes WHERE account_id = ? AND deleted_at IS NOT NULL")
      .bind(account.id).all<{ id: string; r2_key: string | null }>();
    const keys = results.map((r) => r.r2_key).filter((k): k is string => !!k);
    if (keys.length) await env.FAXES.delete(keys);
    await env.DB.prepare("DELETE FROM faxes WHERE account_id = ? AND deleted_at IS NOT NULL").bind(account.id).run();
    return json({ deleted: results.length });
  });
}
