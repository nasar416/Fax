import type { AccountRow, Env } from "./env";
import { sha256Hex } from "./crypto";
import { HttpError, now } from "./http";
import { parseProductId, type Period, type Plan } from "./plans";

/** The parts of RevenueCat's GET /v1/subscribers/{app_user_id} answer that Faxlane uses. */
export interface Subscriber {
  subscriptions: Record<string, {
    expires_date: string | null;
    purchase_date: string;
    refunded_at?: string | null;
    store?: string;
  }>;
  non_subscriptions: Record<string, {
    id: string;
    store_transaction_id?: string;
    purchase_date: string;
    store?: string;
  }[]>;
}

/**
 * Reads a customer's purchases from RevenueCat. The app user ID is the Faxlane account ID
 * (the app calls Purchases.logIn with it), so the answer always belongs to this account.
 */
export async function getSubscriber(env: Env, appUserId: string): Promise<Subscriber> {
  const res = await fetch(`https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(appUserId)}`, {
    headers: { authorization: `Bearer ${env.REVENUECAT_SECRET_KEY}`, accept: "application/json" },
  });
  if (!res.ok) {
    console.error("RevenueCat API error", res.status, await res.text());
    throw new HttpError(502, "revenuecat_error", "We couldn’t check your purchases. Try again.");
  }
  const { subscriber } = (await res.json()) as { subscriber: Partial<Subscriber> };
  return { subscriptions: subscriber.subscriptions ?? {}, non_subscriptions: subscriber.non_subscriptions ?? {} };
}

const RANK: Record<Plan, number> = { basic: 1, premium: 2, business: 3, enterprise: 4 };

/**
 * Makes the account match what RevenueCat says it owns: the best active plan, and every
 * page pack credited exactly once. Safe to run any number of times.
 */
export async function syncPurchases(env: Env, account: AccountRow): Promise<void> {
  const subscriber = await getSubscriber(env, account.id);
  const ts = now();

  // Page packs. The transaction ID is the primary key, so a pack is never credited twice,
  // even if two syncs run at the same moment.
  for (const [productId, purchases] of Object.entries(subscriber.non_subscriptions)) {
    const product = parseProductId(productId);
    if (product?.kind !== "pages") continue;
    for (const p of purchases) {
      const inserted = await env.DB.prepare(
        "INSERT OR IGNORE INTO transactions (transaction_id, original_transaction_id, account_id, product_id, pages_added, created_at) VALUES (?, ?, ?, ?, ?, ?)",
      ).bind(p.store_transaction_id ?? p.id, p.id, account.id, productId, product.pages, ts).run();
      if (inserted.meta.changes === 1) {
        await env.DB.prepare("UPDATE accounts SET extra_pages = extra_pages + ? WHERE id = ?").bind(product.pages, account.id).run();
      }
    }
  }

  // Subscriptions: pick the highest active plan.
  let best: { plan: Plan; period: Period; expiresAt: number | null } | null = null;
  for (const [productId, sub] of Object.entries(subscriber.subscriptions)) {
    const product = parseProductId(productId);
    if (product?.kind !== "subscription" || sub.refunded_at) continue;
    const expiresAt = sub.expires_date ? Math.floor(Date.parse(sub.expires_date) / 1000) : null;
    if (expiresAt !== null && expiresAt <= ts) continue;
    if (!best || RANK[product.plan] > RANK[best.plan] || (RANK[product.plan] === RANK[best.plan] && (expiresAt ?? Infinity) > (best.expiresAt ?? Infinity))) {
      best = { plan: product.plan, period: product.period, expiresAt };
    }
  }

  if (best) {
    // A new plan (or a change of plan) starts a fresh page cycle. Renewals don't.
    const isNew = account.plan !== best.plan || account.period !== best.period;
    await env.DB.prepare(
      `UPDATE accounts SET plan = ?, period = ?, plan_expires_at = ?,
       cycle_start = CASE WHEN ? THEN ? ELSE cycle_start END, pages_used = CASE WHEN ? THEN 0 ELSE pages_used END
       WHERE id = ?`,
    ).bind(best.plan, best.period, best.expiresAt, isNew ? 1 : 0, ts, isNew ? 1 : 0, account.id).run();
    await env.DB.prepare("UPDATE numbers SET release_after = NULL WHERE account_id = ?").bind(account.id).run();
  } else if (account.plan) {
    // Plan ended: hold the numbers for 14 days, then the daily job releases them.
    await env.DB.batch([
      env.DB.prepare("UPDATE accounts SET plan = NULL, period = NULL WHERE id = ?").bind(account.id),
      env.DB.prepare("UPDATE numbers SET release_after = ? WHERE account_id = ? AND release_after IS NULL").bind(ts + 14 * 86400, account.id),
    ]);
  }
}

/** A refunded page pack: take the pages back once (the balance may go below zero). */
export async function revokePagePack(env: Env, transactionIds: string[]): Promise<void> {
  for (const id of transactionIds) {
    const row = await env.DB.prepare("SELECT transaction_id, account_id, pages_added FROM transactions WHERE (transaction_id = ? OR original_transaction_id = ?) AND revoked = 0")
      .bind(id, id).first<{ transaction_id: string; account_id: string; pages_added: number }>();
    if (!row) continue;
    const done = await env.DB.prepare("UPDATE transactions SET revoked = 1 WHERE transaction_id = ? AND revoked = 0").bind(row.transaction_id).run();
    if (done.meta.changes === 1) {
      await env.DB.prepare("UPDATE accounts SET extra_pages = extra_pages - ? WHERE id = ?").bind(row.pages_added, row.account_id).run();
    }
  }
}

/** RevenueCat sends the Authorization value you set on the webhook. Compared through hashes. */
export async function webhookAuthorized(env: Env, header: string | null): Promise<boolean> {
  if (!env.REVENUECAT_WEBHOOK_AUTH || !header) return false;
  const got = await sha256Hex(header.trim());
  return got === (await sha256Hex(env.REVENUECAT_WEBHOOK_AUTH)) || got === (await sha256Hex(`Bearer ${env.REVENUECAT_WEBHOOK_AUTH}`));
}

export interface RevenueCatEvent {
  type?: string;
  app_user_id?: string;
  original_app_user_id?: string;
  aliases?: string[];
  transferred_from?: string[];
  transferred_to?: string[];
  product_id?: string;
  transaction_id?: string;
  original_transaction_id?: string;
  cancel_reason?: string;
}
