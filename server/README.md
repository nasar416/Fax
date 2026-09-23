# Faxlane API (Cloudflare Worker)

This is the backend for the Faxlane iOS app. It runs on Cloudflare Workers, stores data in D1 (SQLite) and keeps fax PDFs in R2. Faxes go out and come in through Telnyx.

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

- Pages are charged atomically.
- At most 50 faxes a day per account, and 50 pages per fax.
- Faxes only go to countries on the `ALLOWED_DIAL_CODES` list.
- Premium-rate US numbers (900 and 976) are blocked.
- Webhook signatures are verified.
- The app's account tokens are stored only as hashes.

## Deploy (from your Mac)

```bash
cd server
npm install
npx wrangler login                                  # opens the browser; pick the Faxlane Cloudflare account

npx wrangler d1 create faxlane                      # copy database_id into wrangler.toml
npx wrangler r2 bucket create faxlane-faxes
npm run db:init                                     # creates the tables

npx wrangler secret put TELNYX_API_KEY              # paste when asked; never commit it
npx wrangler secret put TELNYX_PUBLIC_KEY
npx wrangler secret put MEDIA_SIGNING_SECRET        # e.g. output of: openssl rand -hex 32
npx wrangler secret put REVENUECAT_SECRET_KEY       # RevenueCat API v2 secret key (sk_...)
npx wrangler secret put REVENUECAT_WEBHOOK_AUTH     # e.g. output of: openssl rand -hex 32

npm run deploy
```

Then do the following:

1. In `wrangler.toml`, set these values and run `npm run deploy` again:
   - `PUBLIC_BASE_URL`: the URL that `deploy` printed.
   - `TELNYX_FAX_APP_ID`: your Telnyx Fax Application ID.
   - `SHARED_FROM_NUMBER`: the number free users send from.
2. In Telnyx, open your Fax Application and set the webhook URL to `https://<your-worker>/v1/webhooks/telnyx`.
3. In RevenueCat, go to Integrations → Webhooks → Add. Set the URL to `https://<your-worker>/v1/webhooks/revenuecat` and the Authorization header to the same value as `REVENUECAT_WEBHOOK_AUTH`. Send events for both production and sandbox.
4. In the iOS project (`project.yml` → `FaxlaneAPIBaseURL`), set the Worker URL. Run `xcodegen generate` again.

To change remote config without an App Store update, run SQL like this:

```bash
npx wrangler d1 execute faxlane --remote --command "INSERT OR REPLACE INTO config VALUES ('announcement', '\"New: fax to 40+ countries\"')"
```

## Develop and test

```bash
npm test          # 23 tests: pages, refunds, webhooks, purchases, locked faxes, blocking, daily job
npm run typecheck
npm run dev       # local Worker with local D1/R2
```

The tests use an in-memory SQLite database in place of D1, and mock Telnyx and RevenueCat. They need Node 22 or later.

## Notes

- **Blocked senders:** Telnyx delivers a received fax before our server sees it. So a blocked sender still costs you Telnyx's per-page price, but the user's pages are never charged.
- **Purchases:** the app buys through the RevenueCat SDK, with the Faxlane account ID as the RevenueCat App User ID. The server never trusts the app's word: it always reads the customer from RevenueCat's API.
- **Refund requests:** Apple's "consumption information" answer isn't sent yet. The `share_usage` flag is already stored for when it is.
