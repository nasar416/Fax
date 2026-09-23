-- Faxlane database schema (SQLite). The Database Durable Object applies it on start (src/db.ts).
CREATE TABLE IF NOT EXISTS accounts (
  id TEXT PRIMARY KEY,
  apple_sub TEXT UNIQUE,
  created_at INTEGER NOT NULL,
  plan TEXT,                         -- basic | premium | business | enterprise | NULL (free)
  period TEXT,                       -- weekly | monthly | annual
  plan_expires_at INTEGER,
  cycle_start INTEGER NOT NULL,
  pages_used INTEGER NOT NULL DEFAULT 0,
  extra_pages INTEGER NOT NULL DEFAULT 0,
  free_pages_left INTEGER NOT NULL DEFAULT 3,
  retention_days INTEGER NOT NULL DEFAULT 30,
  paused_until INTEGER,
  share_usage INTEGER NOT NULL DEFAULT 0,
  sending_number TEXT
);

-- One account can be used on several devices; each device keeps its own token.
CREATE TABLE IF NOT EXISTS tokens (
  token_hash TEXT PRIMARY KEY,
  account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS tokens_account ON tokens(account_id);

CREATE TABLE IF NOT EXISTS numbers (
  e164 TEXT PRIMARY KEY,
  account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  label TEXT NOT NULL DEFAULT '',
  telnyx_order_id TEXT,
  created_at INTEGER NOT NULL,
  release_after INTEGER             -- set when the plan ends; released by the daily job
);
CREATE INDEX IF NOT EXISTS numbers_account ON numbers(account_id);

CREATE TABLE IF NOT EXISTS faxes (
  id TEXT PRIMARY KEY,
  account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  direction TEXT NOT NULL,           -- sent | received
  party_number TEXT NOT NULL,
  own_number TEXT NOT NULL,
  pages INTEGER NOT NULL,
  cost INTEGER NOT NULL DEFAULT 0,   -- pages charged to the account
  charge_plan INTEGER NOT NULL DEFAULT 0,
  charge_extra INTEGER NOT NULL DEFAULT 0,
  charge_free INTEGER NOT NULL DEFAULT 0,
  state TEXT NOT NULL,               -- queued | sending | delivered | failed | received | locked
  telnyx_fax_id TEXT UNIQUE,
  r2_key TEXT,
  failure_reason TEXT,
  unread INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER
);
CREATE INDEX IF NOT EXISTS faxes_account ON faxes(account_id, created_at);

CREATE TABLE IF NOT EXISTS blocked (
  account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  e164 TEXT NOT NULL,
  reason TEXT NOT NULL DEFAULT '',
  created_at INTEGER NOT NULL,
  PRIMARY KEY (account_id, e164)
);

-- Every page-pack purchase credited (from RevenueCat), so nothing is counted twice.
CREATE TABLE IF NOT EXISTS transactions (
  transaction_id TEXT PRIMARY KEY,
  original_transaction_id TEXT NOT NULL,
  account_id TEXT NOT NULL,
  product_id TEXT NOT NULL,
  pages_added INTEGER NOT NULL DEFAULT 0,
  revoked INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL
);

-- Remote config read by the app (GET /v1/config). Value is JSON.
CREATE TABLE IF NOT EXISTS config (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
