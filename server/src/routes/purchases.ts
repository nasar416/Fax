import type { AccountRow, Env } from "../env";
import { publicAccount, requireAccount } from "../accounts";
import { HttpError, json, readJson, type Router } from "../http";
import { parseProductId } from "../plans";
import { revokePagePack, syncPurchases, webhookAuthorized, type RevenueCatEvent } from "../revenuecat";

export function purchaseRoutes(router: Router, env: Env) {
  /** Called by the app after a purchase or restore. The server asks RevenueCat what the account owns. */
  router.on("POST", "/v1/purchases", async (request) => {
    const account = await requireAccount(request, env);
    await syncPurchases(env, account);
    const updated = (await env.DB.prepare("SELECT * FROM accounts WHERE id = ?").bind(account.id).first<AccountRow>())!;
    const { results } = await env.DB.prepare("SELECT e164, label FROM numbers WHERE account_id = ?").bind(account.id).all<{ e164: string; label: string }>();
    return json(publicAccount(updated, results));
  });

  /**
   * RevenueCat webhook: purchases, renewals, expiry, refunds and transfers.
   * The event only says which customer changed; the account is then re-read from RevenueCat's API,
   * so a forged event can't give anyone a plan.
   */
  router.on("POST", "/v1/webhooks/revenuecat", async (request) => {
    if (!(await webhookAuthorized(env, request.headers.get("authorization")))) throw new HttpError(401, "unauthorized");
    const { event } = await readJson<{ event?: RevenueCatEvent }>(request);
    if (!event) throw new HttpError(400, "missing_event");

    // Refunded page pack (a refunded subscription shows up as refunded in the sync below).
    const product = event.product_id ? parseProductId(event.product_id) : null;
    if (event.type === "CANCELLATION" && product?.kind === "pages" && event.cancel_reason === "CUSTOMER_SUPPORT") {
      await revokePagePack(env, [event.transaction_id, event.original_transaction_id].filter((x): x is string => !!x));
    }

    const ids = new Set([event.app_user_id, event.original_app_user_id, ...(event.aliases ?? []),
      ...(event.transferred_from ?? []), ...(event.transferred_to ?? [])].filter((x): x is string => !!x && !x.startsWith("$RCAnonymousID")));
    for (const id of ids) {
      const account = await env.DB.prepare("SELECT * FROM accounts WHERE id = ?").bind(id).first<AccountRow>();
      if (account) await syncPurchases(env, account);
    }
    return json({ ok: true });
  });
}
