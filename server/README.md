# Faxlane API (Cloudflare Worker)

This is the backend for the Faxlane iOS app. It runs on Cloudflare Workers, stores data in SQLite inside a Durable Object (`src/db.ts`, free plan) and keeps fax PDFs in R2.

**Live:** https://faxlane-api.faxlane.workers.dev · Telnyx Fax Application `Faxlane` (3055251109728748786) with number +1 618 674 1234 · RevenueCat webhook set. Faxes go out and come in through Telnyx.

The Telnyx API key lives only here, as an encrypted Worker secret. The app never sees it.

## What it does

| Endpoint | Purpose |
|---|---|
| `POST /v1/accounts` | Registers the device's account token and creates a guest account with 3 free pages. |
| `GET/PATCH/DELETE /v1/me` | Returns the account, changes settings (retention, pause, sending number), or deletes the account with its faxes, files and numbers. |
| `POST /v1/auth/apple` | Sign in with Apple. The identity token is verified against Apple's keys. |
| `POST /v1/faxes` | Sends a fax: a PDF upload (multipart). Pages are charged atomically. International pages count 3×. |
| `GET /v1/faxes?folder=inbox\|sent\|outbox\|trash` | Lists faxes. |
| `GET /v1/faxes/:id` | Fax details. |
| `GET /v1/faxes/:id/pdf` | Fax file. Locked faxes return 402. |
| `PATCH /v1/faxes/:id` | Marks read or moves to Trash. |
| `POST /v1/faxes/:id/unlock` | Opens a locked fax once the account has pages. |
| `DELETE /v1/trash` | Empties Trash. |
| `POST /v1/purchases` | Called by the app after a purchase or restore. The server asks RevenueCat what the account owns, then sets the plan and adds page-pack pages (each pack only once). |
| `POST /v1/webhooks/telnyx` | Telnyx events: sending, delivered (real page count), failed (all pages refunded), received. Every event's Ed25519 signature is checked. |
| `POST /v1/webhooks/revenuecat` | RevenueCat events: purchases, renewals, expiry, refunds, transfers. The Authorization header is checked, then the account is re-read from RevenueCat's API. |
| `GET/POST/DELETE /v1/blocked` | Blocked numbers. Faxes from them are dropped and cost the user no pages. |
| `GET /v1/numbers/available`, `POST /v1/numbers` | Search and order fax numbers (paid plans, up to the plan's limit). |
| `GET /v1/config` | Remote config for the app, read from the `config` table. |
| `GET /v1/media/:id` | Signed, expiring link Telnyx uses to download an outgoing PDF. |

The daily cron job does three things:

- Starts a new page cycle for each active plan.
- Erases faxes older than each account's retention setting, and Trash items older than 30 days.
- Releases numbers 14 days after a plan ends.

Built-in protections:

- Pages are charged atomically, and the server counts the pages in each PDF itself, so an app can't under-report them.
- Page cost follows call cost: US/Canada 1×, low-cost countries 3×, other allowed countries 10×.
- Toll fraud: premium, personal and Caribbean +1 area codes are blocked (they look domestic but bill internationally), only countries on `ALLOWED_DIAL_CODES` can be dialed, and the Telnyx outbound profile has its own country whitelist.
- Free pages: after 5 new accounts from one network in a day, new accounts get no free pages.
- Free trials: capped at 10 pages and no own number until the first paid period.
- Failed faxes: pages that already went through count; the rest are given back. Real page counts above the charge are always collected.
- Missed webhooks: the daily job re-checks plans past their expiry with RevenueCat.
- Numbers are released only if they are on the Faxlane Fax Application; the shared number never is.
- At most 50 faxes a day per account, and 50 pages per fax. Webhook signatures are verified. Account tokens are stored only as hashes.

## Deploy

```bash
cd server
npm install
npx wrangler login                                  # or set CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID
npx wrangler r2 bucket create faxlane-faxes         # once
npx wrangler secret put TELNYX_API_KEY              # Telnyx API v2 key
npx wrangler secret put TELNYX_PUBLIC_KEY           # Telnyx webhook public key
npx wrangler secret put MEDIA_SIGNING_SECRET        # e.g. openssl rand -hex 32
npx wrangler secret put REVENUECAT_SECRET_KEY       # RevenueCat API v2 secret key (sk_...)
npx wrangler secret put REVENUECAT_WEBHOOK_AUTH     # e.g. openssl rand -hex 32
npm run deploy
```

The database needs no setup: the `Database` Durable Object creates its tables on first start.

Webhooks: Telnyx Fax Application → `https://<worker>/v1/webhooks/telnyx`; RevenueCat → `https://<worker>/v1/webhooks/revenuecat` with the `REVENUECAT_WEBHOOK_AUTH` value as the Authorization header.

Remote config (announcement, maintenance, minimum version) lives in the `config` table. Change a row there to update the app without an App Store release.

## Develop and test

```bash
npm test          # 23 tests: pages, refunds, webhooks, purchases, locked faxes, blocking, daily job
npm run typecheck
npm run dev       # local Worker with a local database and R2
```

The tests use an in-memory SQLite database in place of the Durable Object, and mock Telnyx and RevenueCat. They need Node 22 or later.

## Notes

- **Blocked senders:** Telnyx delivers a received fax before our server sees it. So a blocked sender still costs you Telnyx's per-page price, but the user's pages are never charged.
- **Purchases:** the app buys through the RevenueCat SDK, with the Faxlane account ID as the RevenueCat App User ID. The server never trusts the app's word: it always reads the customer from RevenueCat's API.
- **Refund requests:** Apple's "consumption information" answer isn't sent yet. The `share_usage` flag is already stored for when it is.
