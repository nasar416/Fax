import type { AccountRow, Env } from "./env";
import { sha256Hex } from "./crypto";
import { HttpError, now } from "./http";
import { parseProductId, type Period, type Plan } from "./plans";

const API = "https://api.revenuecat.com/v2";

/** The parts of RevenueCat's API v2 answers that Faxlane uses. Times are in milliseconds. */
export interface Subscriber {
  subscriptions: { product: string; givesAccess: boolean; endsAt: number | null; trial: boolean }[];
  purchases: { id: string; storeId: string | null; product: string; refunded: boolean }[];
}

async function rc<T>(env: Env, path: string): Promise<T | null> {
  const res = await fetch(`${API}/projects/${env.REVENUECAT_PROJECT_ID}${path}`, {
    headers: { authorization: `Bearer ${env.REVENUECAT_SECRET_KEY}`, accept: "application/json" },
  });
  if (res.status === 404) return null;
  if (!res.ok) {
    console.error("RevenueCat API error", res.status, await res.text());
    throw new HttpError(502, "revenuecat_error", "We couldn’t check your purchases. Try again.");
  }
  return (await res.json()) as T;
}

/** Follows RevenueCat's next_page links (a customer rarely has more than one page). */
async function list<T>(env: Env, path: string): Promise<T[]> {
  const items: T[] = [];
  let next: string | null = path;
  for (let i = 0; next && i < 10; i++) {
    const page: { items: T[]; next_page: string | null } | null = await rc(env, next);
    if (!page) break;
    items.push(...page.items);
    next = page.next_page ? page.next_page.replace(/^.*\/projects\/[^/]+/, "") : null;
  }
  return items;
}

/** RevenueCat product ID → App Store product ID. Cached while the Worker stays warm. */
let productCache: Map<string, string> | null = null;
async function storeIdentifier(env: Env, rcProductId: string): Promise<string | undefined> {
  if (!productCache?.has(rcProductId)) {
    const products = await list<{ id: string; store_identifier: string }>(env, "/products?limit=100");
    productCache = new Map(products.map((p) => [p.id, p.store_identifier]));
  }
  return productCache.get(rcProductId);
}

/**
 * Reads a customer's purchases from RevenueCat. The customer ID is the Faxlane account ID
 * (the app calls Purchases.logIn with it), so the answer always belongs to this account.
 */
export async function getSubscriber(env: Env, appUserId: string): Promise<Subscriber> {
  const id = encodeURIComponent(appUserId);
  const subs = await list<{ product_id: string; gives_access: boolean; current_period_ends_at: number | null; status?: string }>(env, `/customers/${id}/subscriptions?limit=100`);
  const buys = await list<{ id: string; product_id: string; status: string; store_purchase_identifier?: string | null }>(env, `/customers/${id}/purchases?limit=100`);
  return {
    subscriptions: await Promise.all(subs.map(async (s) => ({
      product: (await storeIdentifier(env, s.product_id)) ?? "", givesAccess: s.gives_access, endsAt: s.current_period_ends_at, trial: s.status === "trialing",
    }))),
    purchases: await Promise.all(buys.map(async (p) => ({
      id: p.id, storeId: p.store_purchase_identifier ?? null, product: (await storeIdentifier(env, p.product_id)) ?? "", refunded: p.status === "refunded",
    }))),
  };
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
  // even if two syncs run at the same moment. Refunded packs are taken back once.
  for (const p of subscriber.purchases) {
    const product = parseProductId(p.product);
    if (product?.kind !== "pages") continue;
    if (p.refunded) {
      await revokePagePack(env, [p.storeId ?? p.id]);
      continue;
    }
    const inserted = await env.DB.prepare(
      "INSERT OR IGNORE INTO transactions (transaction_id, original_transaction_id, account_id, product_id, pages_added, created_at) VALUES (?, ?, ?, ?, ?, ?)",
    ).bind(p.storeId ?? p.id, p.id, account.id, p.product, product.pages, ts).run();
    if (inserted.meta.changes === 1) {
      await env.DB.prepare("UPDATE accounts SET extra_pages = extra_pages + ? WHERE id = ?").bind(product.pages, account.id).run();
    }
  }

  // Subscriptions: pick the highest active plan.
  let best: { plan: Plan; period: Period; expiresAt: number | null; trial: boolean } | null = null;
  for (const sub of subscriber.subscriptions) {
    const product = parseProductId(sub.product);
    if (product?.kind !== "subscription" || !sub.givesAccess) continue;
    const expiresAt = sub.endsAt ? Math.floor(sub.endsAt / 1000) : null;
    if (!best || RANK[product.plan] > RANK[best.plan] || (RANK[product.plan] === RANK[best.plan] && (expiresAt ?? Infinity) > (best.expiresAt ?? Infinity))) {
      best = { plan: product.plan, period: product.period, expiresAt, trial: sub.trial };
    }
  }

  if (best) {
    // A new plan (or a change of plan) starts a fresh page cycle. Renewals don't.
    const isNew = account.plan !== best.plan || account.period !== best.period;
    await env.DB.prepare(
      `UPDATE accounts SET plan = ?, period = ?, plan_expires_at = ?, in_trial = ?,
       cycle_start = CASE WHEN ? THEN ? ELSE cycle_start END, pages_used = CASE WHEN ? THEN 0 ELSE pages_used END
       WHERE id = ?`,
    ).bind(best.plan, best.period, best.expiresAt, best.trial ? 1 : 0, isNew ? 1 : 0, ts, isNew ? 1 : 0, account.id).run();
    await env.DB.prepare("UPDATE numbers SET release_after = NULL WHERE account_id = ?").bind(account.id).run();
  } else if (account.plan) {
    // Plan ended: hold the numbers for 14 days, then the daily job releases them.
    await env.DB.batch([
      env.DB.prepare("UPDATE accounts SET plan = NULL, period = NULL, in_trial = 0 WHERE id = ?").bind(account.id),
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
