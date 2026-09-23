import type { AccountRow, Env, FaxRow } from "../env";
import { charge, refund } from "../accounts";
import { getTransaction, type NotificationPayload } from "../appstore";
import { decodeJwsPayload, randomId, verifyTelnyxSignature } from "../crypto";
import { HttpError, json, now, type Router } from "../http";
import { pageMultiplier, toE164 } from "../phone";
import { downloadMedia } from "../telnyx";
import { applyTransaction } from "./purchases";

interface TelnyxEvent {
  data?: {
    id?: string;
    event_type?: string;
    payload?: {
      fax_id?: string;
      id?: string;
      from?: string;
      to?: string;
      page_count?: number;
      media_url?: string;
      failure_reason?: string;
      status?: string;
      direction?: string;
    };
  };
}

export function webhookRoutes(router: Router, env: Env) {
  /** Telnyx fax events: sending progress, delivery, failure and incoming faxes. */
  router.on("POST", "/v1/webhooks/telnyx", async (request) => {
    const body = await request.text();
    const signature = request.headers.get("telnyx-signature-ed25519") ?? "";
    const timestamp = request.headers.get("telnyx-timestamp") ?? "";
    if (Math.abs(now() - Number(timestamp)) > 300 || !(await verifyTelnyxSignature(env.TELNYX_PUBLIC_KEY, timestamp, body, signature))) {
      throw new HttpError(401, "bad_signature");
    }
    const event = JSON.parse(body) as TelnyxEvent;
    const type = event.data?.event_type ?? "";
    const p = event.data?.payload ?? {};
    const telnyxFaxId = p.fax_id ?? p.id ?? "";

    if (type === "fax.received") {
      await handleIncoming(env, p);
      return json({ ok: true });
    }

    const fax = await env.DB.prepare("SELECT * FROM faxes WHERE telnyx_fax_id = ?").bind(telnyxFaxId).first<FaxRow>();
    if (!fax) return json({ ok: true, ignored: "unknown fax" });

    if (type === "fax.sending.started" || type === "fax.media.processed" || type === "fax.queued") {
      if (fax.state === "queued") await env.DB.prepare("UPDATE faxes SET state = 'sending', updated_at = ? WHERE id = ?").bind(now(), fax.id).run();
    } else if (type === "fax.delivered" && fax.state !== "delivered") {
      const realPages = p.page_count && p.page_count > 0 ? p.page_count : fax.pages;
      const realCost = realPages * pageMultiplier(fax.party_number);
      if (realCost < fax.cost) {
        // Give back the difference, plan pages first.
        const back = fax.cost - realCost;
        const fromPlan = Math.min(back, fax.charge_plan);
        const fromExtra = Math.min(back - fromPlan, fax.charge_extra);
        await refund(env, fax.account_id, { fromPlan, fromExtra, fromFree: back - fromPlan - fromExtra });
      } else if (realCost > fax.cost) {
        await charge(env, fax.account_id, realCost - fax.cost); // best effort; never blocks delivery
      }
      await env.DB.prepare("UPDATE faxes SET state = 'delivered', pages = ?, cost = ?, updated_at = ? WHERE id = ?")
        .bind(realPages, realCost, now(), fax.id).run();
    } else if (type === "fax.failed" && fax.state !== "failed") {
      await refund(env, fax.account_id, { fromPlan: fax.charge_plan, fromExtra: fax.charge_extra, fromFree: fax.charge_free });
      await env.DB.prepare("UPDATE faxes SET state = 'failed', cost = 0, failure_reason = ?, updated_at = ? WHERE id = ?")
        .bind(readableFailure(p.failure_reason), now(), fax.id).run();
    }
    return json({ ok: true });
  });

  /**
   * App Store Server Notifications V2. The payload is decoded, then the transaction is
   * re-fetched from Apple's API, so a forged notification can't change anything.
   */
  router.on("POST", "/v1/webhooks/appstore", async (request) => {
    const { signedPayload } = (await request.json()) as { signedPayload?: string };
    if (!signedPayload) throw new HttpError(400, "missing_payload");
    const notification = decodeJwsPayload<NotificationPayload>(signedPayload);
    const signedTx = notification.data?.signedTransactionInfo;
    if (!signedTx) return json({ ok: true });
    const claimed = decodeJwsPayload<{ transactionId: string }>(signedTx);
    const tx = await getTransaction(env, claimed.transactionId);
    await applyTransaction(env, tx, null, notification.notificationType);
    return json({ ok: true });
  });
}

function readableFailure(reason?: string): string {
  switch (reason) {
    case "user_busy": return "The line was busy. No pages were used from your plan.";
    case "no_answer": return "Nobody answered. No pages were used from your plan.";
    case "receiver_incompatible_destination":
    case "invalid_number_format":
    case "destination_invalid": return "This number isn’t a fax machine. No pages were used from your plan.";
    default: return "The fax didn’t go through. No pages were used from your plan.";
  }
}

async function handleIncoming(env: Env, p: NonNullable<NonNullable<TelnyxEvent["data"]>["payload"]>) {
  const to = toE164(p.to ?? "");
  const from = toE164(p.from ?? "") ?? (p.from ?? "unknown");
  if (!to || !p.media_url) return;
  const telnyxFaxId = p.fax_id ?? p.id ?? randomId();
  const existing = await env.DB.prepare("SELECT 1 FROM faxes WHERE telnyx_fax_id = ?").bind(telnyxFaxId).first();
  if (existing) return;

  const owner = await env.DB.prepare("SELECT a.* FROM numbers n JOIN accounts a ON a.id = n.account_id WHERE n.e164 = ?")
    .bind(to).first<AccountRow>();
  if (!owner) return;

  // Blocked senders and paused numbers: drop the fax and never charge the user's pages.
  if (owner.paused_until && owner.paused_until > now()) return;
  const blocked = await env.DB.prepare("SELECT 1 FROM blocked WHERE account_id = ? AND e164 = ?").bind(owner.id, from).first();
  if (blocked) return;

  const pages = Math.max(p.page_count ?? 1, 1);
  const id = randomId();
  const key = `in/${owner.id}/${id}.pdf`;
  await env.FAXES.put(key, await downloadMedia(p.media_url), { httpMetadata: { contentType: "application/pdf" } });

  // Received pages count. With no pages left the fax is kept but locked until pages are added.
  const paid = await charge(env, owner.id, pages);
  const ts = now();
  await env.DB.prepare(
    `INSERT INTO faxes (id, account_id, direction, party_number, own_number, pages, cost, charge_plan, charge_extra, charge_free, state, telnyx_fax_id, r2_key, unread, created_at, updated_at)
     VALUES (?, ?, 'received', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?)`,
  ).bind(id, owner.id, from, to, pages, paid ? pages : 0, paid?.fromPlan ?? 0, paid?.fromExtra ?? 0, paid?.fromFree ?? 0,
    paid ? "received" : "locked", telnyxFaxId, key, ts, ts).run();
}
