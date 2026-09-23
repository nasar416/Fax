import type { AccountRow, Env } from "../env";
import { publicAccount, requireAccount, tokenBelongsTo } from "../accounts";
import { getTransaction, type TransactionInfo } from "../appstore";
import { HttpError, json, now, readJson, type Router } from "../http";
import { parseProductId } from "../plans";

export function purchaseRoutes(router: Router, env: Env) {
  /** Called by the app right after a StoreKit purchase (and on restore) with the transaction ID. */
  router.on("POST", "/v1/purchases", async (request) => {
    const account = await requireAccount(request, env);
    const body = await readJson<{ transactionId?: string }>(request);
    if (!body.transactionId) throw new HttpError(400, "missing_transaction");
    const tx = await getTransaction(env, body.transactionId);
    await applyTransaction(env, tx, account, "APP_REPORTED");
    const updated = (await env.DB.prepare("SELECT * FROM accounts WHERE id = ?").bind(account.id).first<AccountRow>())!;
    const { results } = await env.DB.prepare("SELECT e164, label FROM numbers WHERE account_id = ?").bind(account.id).all<{ e164: string; label: string }>();
    return json(publicAccount(updated, results));
  });
}

/**
 * Applies a transaction verified with Apple. `reporter` is the account that sent it (null for
 * server notifications). The account is found through appAccountToken or the original transaction.
 */
export async function applyTransaction(env: Env, tx: TransactionInfo, reporter: AccountRow | null, reason: string): Promise<void> {
  const product = parseProductId(tx.productId);
  if (!product) return;

  let account: AccountRow | null = null;
  if (reporter && (await tokenBelongsTo(env, reporter.id, tx.appAccountToken))) account = reporter;
  if (!account) {
    account = await env.DB.prepare("SELECT * FROM accounts WHERE original_transaction_id = ?").bind(tx.originalTransactionId).first<AccountRow>();
  }
  if (!account && reporter && !tx.appAccountToken) account = reporter; // purchases made before accounts existed
  if (!account) {
    const prior = await env.DB.prepare("SELECT account_id FROM transactions WHERE original_transaction_id = ?").bind(tx.originalTransactionId).first<{ account_id: string }>();
    if (prior) account = await env.DB.prepare("SELECT * FROM accounts WHERE id = ?").bind(prior.account_id).first<AccountRow>();
  }
  if (!account) return;

  const ts = now();
  const revoked = !!tx.revocationDate || reason === "REFUND" || reason === "REVOKE";
  const seen = await env.DB.prepare("SELECT * FROM transactions WHERE transaction_id = ?").bind(tx.transactionId)
    .first<{ pages_added: number; revoked: number }>();

  if (product.kind === "pages") {
    if (!seen && !revoked) {
      await env.DB.batch([
        env.DB.prepare("INSERT INTO transactions (transaction_id, original_transaction_id, account_id, product_id, pages_added, created_at) VALUES (?, ?, ?, ?, ?, ?)")
          .bind(tx.transactionId, tx.originalTransactionId, account.id, tx.productId, product.pages, ts),
        env.DB.prepare("UPDATE accounts SET extra_pages = extra_pages + ? WHERE id = ?").bind(product.pages, account.id),
      ]);
    } else if (seen && revoked && !seen.revoked) {
      // Refunded page pack: take the pages back (the balance may go below zero).
      await env.DB.batch([
        env.DB.prepare("UPDATE transactions SET revoked = 1 WHERE transaction_id = ?").bind(tx.transactionId),
        env.DB.prepare("UPDATE accounts SET extra_pages = extra_pages - ? WHERE id = ?").bind(seen.pages_added, account.id),
      ]);
    }
    return;
  }

  // Subscription
  if (!seen) {
    await env.DB.prepare("INSERT INTO transactions (transaction_id, original_transaction_id, account_id, product_id, created_at) VALUES (?, ?, ?, ?, ?)")
      .bind(tx.transactionId, tx.originalTransactionId, account.id, tx.productId, ts).run();
  }
  const expiresAt = tx.expiresDate ? Math.floor(tx.expiresDate / 1000) : null;
  const active = !revoked && (expiresAt === null || expiresAt > ts);
  if (active) {
    const isNewPurchase = !seen && (account.plan !== product.plan || account.original_transaction_id !== tx.originalTransactionId);
    await env.DB.prepare(
      `UPDATE accounts SET plan = ?, period = ?, plan_expires_at = ?, original_transaction_id = ?,
       cycle_start = CASE WHEN ? THEN ? ELSE cycle_start END, pages_used = CASE WHEN ? THEN 0 ELSE pages_used END
       WHERE id = ?`,
    ).bind(product.plan, product.period, expiresAt, tx.originalTransactionId, isNewPurchase ? 1 : 0, ts, isNewPurchase ? 1 : 0, account.id).run();
    await env.DB.prepare("UPDATE numbers SET release_after = NULL WHERE account_id = ?").bind(account.id).run();
  } else {
    // Plan ended: hold the numbers for 14 days, then the daily job releases them.
    await env.DB.batch([
      env.DB.prepare("UPDATE accounts SET plan = NULL, period = NULL, plan_expires_at = ? WHERE id = ? AND original_transaction_id = ?")
        .bind(expiresAt, account.id, tx.originalTransactionId),
      env.DB.prepare("UPDATE numbers SET release_after = ? WHERE account_id = ? AND release_after IS NULL").bind(ts + 14 * 86400, account.id),
    ]);
  }
}
