import type { Env } from "./env";
import { decodeJwsPayload, signAppStoreJwt } from "./crypto";
import { HttpError } from "./http";

export interface TransactionInfo {
  transactionId: string;
  originalTransactionId: string;
  bundleId: string;
  productId: string;
  purchaseDate: number;
  expiresDate?: number;
  revocationDate?: number;
  appAccountToken?: string;
  type: string;
  environment: string;
}

const HOSTS = {
  Production: "https://api.storekit.itunes.apple.com",
  Sandbox: "https://api.storekit-sandbox.itunes.apple.com",
} as const;

/**
 * Looks a transaction up with Apple's App Store Server API.
 * The answer comes straight from Apple over TLS, so it is the source of truth.
 * Falls back to the sandbox so TestFlight purchases work too.
 */
export async function getTransaction(env: Env, transactionId: string): Promise<TransactionInfo> {
  const jwt = await signAppStoreJwt({
    issuerId: env.APPSTORE_ISSUER_ID,
    keyId: env.APPSTORE_KEY_ID,
    privateKeyPem: env.APPSTORE_PRIVATE_KEY,
    bundleId: env.BUNDLE_ID,
  });
  const order: (keyof typeof HOSTS)[] = env.APPSTORE_ENVIRONMENT === "Sandbox" ? ["Sandbox", "Production"] : ["Production", "Sandbox"];
  for (const environment of order) {
    const res = await fetch(`${HOSTS[environment]}/inApps/v1/transactions/${encodeURIComponent(transactionId)}`, {
      headers: { authorization: `Bearer ${jwt}` },
    });
    if (res.status === 404) continue;
    if (!res.ok) {
      console.error("App Store API error", res.status, await res.text());
      throw new HttpError(502, "appstore_error", "We couldn’t check this purchase with Apple. Try again.");
    }
    const { signedTransactionInfo } = (await res.json()) as { signedTransactionInfo: string };
    const info = decodeJwsPayload<TransactionInfo>(signedTransactionInfo);
    if (info.bundleId !== env.BUNDLE_ID) throw new HttpError(400, "wrong_app", "This purchase belongs to another app.");
    return info;
  }
  throw new HttpError(404, "transaction_not_found", "Apple doesn’t know this purchase.");
}

export interface NotificationPayload {
  notificationType: string;
  subtype?: string;
  data?: { signedTransactionInfo?: string; bundleId?: string };
}
