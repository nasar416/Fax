export interface Env {
  DB: D1Database;
  FAXES: R2Bucket;

  BUNDLE_ID: string;
  PUBLIC_BASE_URL: string;
  TELNYX_FAX_APP_ID: string;
  SHARED_FROM_NUMBER: string;
  ALLOWED_DIAL_CODES: string;

  TELNYX_API_KEY: string;
  TELNYX_PUBLIC_KEY: string;
  MEDIA_SIGNING_SECRET: string;
  /** RevenueCat secret API key (sk_...), used to read a customer's purchases. */
  REVENUECAT_SECRET_KEY: string;
  /** The Authorization value set on the RevenueCat webhook. */
  REVENUECAT_WEBHOOK_AUTH: string;
}

export interface AccountRow {
  id: string;
  apple_sub: string | null;
  created_at: number;
  plan: string | null;
  period: string | null;
  plan_expires_at: number | null;
  cycle_start: number;
  pages_used: number;
  extra_pages: number;
  free_pages_left: number;
  retention_days: number;
  paused_until: number | null;
  share_usage: number;
  sending_number: string | null;
}

export interface FaxRow {
  id: string;
  account_id: string;
  direction: "sent" | "received";
  party_number: string;
  own_number: string;
  pages: number;
  cost: number;
  charge_plan: number;
  charge_extra: number;
  charge_free: number;
  state: "queued" | "sending" | "delivered" | "failed" | "received" | "locked";
  telnyx_fax_id: string | null;
  r2_key: string | null;
  failure_reason: string | null;
  unread: number;
  created_at: number;
  updated_at: number;
  deleted_at: number | null;
}
