import { afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import { runDaily } from "../src/cron";
import { signedMediaUrl } from "../src/crypto";
import type { Env } from "../src/env";
import { fakeD1, fakeR2 } from "./fakes";

const TOKEN = "3f1c2b8e-9a4d-4c6e-8b1f-2d7e5a9c0b13";
let env: Env;
let d1: ReturnType<typeof fakeD1>;
let r2: ReturnType<typeof fakeR2>;
let telnyxKeys: CryptoKeyPair;
let telnyxSent: unknown[] = [];
let telnyxCounter = 0;
let rcSubscriber: { subscriptions: Record<string, object>; non_subscriptions: Record<string, object[]> } = { subscriptions: {}, non_subscriptions: {} };

const b64 = (buf: ArrayBuffer) => btoa(String.fromCharCode(...new Uint8Array(buf)));
const iso = (msFromNow: number) => new Date(Date.now() + msFromNow).toISOString();

beforeAll(async () => {
  telnyxKeys = (await crypto.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"])) as CryptoKeyPair;
  d1 = fakeD1();
  r2 = fakeR2();
  env = {
    DB: d1 as unknown as D1Database,
    FAXES: r2 as unknown as R2Bucket,
    BUNDLE_ID: "com.faxlane.app",
    PUBLIC_BASE_URL: "https://api.faxlane.test",
    TELNYX_FAX_APP_ID: "fax-app-1",
    SHARED_FROM_NUMBER: "+15550000000",
    ALLOWED_DIAL_CODES: "1,44",
    TELNYX_API_KEY: "test",
    TELNYX_PUBLIC_KEY: b64(await crypto.subtle.exportKey("raw", telnyxKeys.publicKey) as ArrayBuffer),
    MEDIA_SIGNING_SECRET: "media-secret",
    REVENUECAT_SECRET_KEY: "sk_test",
    REVENUECAT_WEBHOOK_AUTH: "hook-secret",
  };

  vi.stubGlobal("fetch", async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input instanceof Request ? input.url : input);
    if (url === "https://api.telnyx.com/v2/faxes") {
      telnyxSent.push(JSON.parse(String(init?.body)));
      return Response.json({ data: { id: `tx-${++telnyxCounter}` } });
    }
    if (url.startsWith("https://api.revenuecat.com/v1/subscribers/")) {
      expect(new Headers(init?.headers).get("authorization")).toBe("Bearer sk_test");
      return Response.json({ subscriber: rcSubscriber });
    }
    if (url === "https://media.telnyx.test/in.pdf") return new Response(new Uint8Array([37, 80, 68, 70]));
    throw new Error(`Unexpected fetch ${url}`);
  });
});

afterEach(() => { telnyxSent = []; });

async function call(method: string, path: string, body?: unknown, auth = true) {
  const headers: Record<string, string> = {};
  if (auth) headers.authorization = `Bearer ${TOKEN}`;
  let payload: BodyInit | undefined;
  if (body instanceof FormData) payload = body;
  else if (body !== undefined) { payload = JSON.stringify(body); headers["content-type"] = "application/json"; }
  const res = await worker.fetch(new Request(`https://api.faxlane.test${path}`, { method, headers, body: payload }), env);
  return { status: res.status, body: res.headers.get("content-type")?.includes("json") ? await res.json() as any : await res.arrayBuffer() };
}

async function revenueCatEvent(event: object, auth = "hook-secret") {
  const res = await worker.fetch(new Request("https://api.faxlane.test/v1/webhooks/revenuecat", {
    method: "POST", body: JSON.stringify({ event }), headers: { authorization: auth, "content-type": "application/json" },
  }), env);
  return res.status;
}

async function telnyxEvent(event_type: string, payload: object) {
  const body = JSON.stringify({ data: { event_type, payload } });
  const ts = String(Math.floor(Date.now() / 1000));
  const sig = b64(await crypto.subtle.sign("Ed25519", telnyxKeys.privateKey, new TextEncoder().encode(`${ts}|${body}`)) as ArrayBuffer);
  const res = await worker.fetch(new Request("https://api.faxlane.test/v1/webhooks/telnyx", {
    method: "POST", body, headers: { "telnyx-signature-ed25519": sig, "telnyx-timestamp": ts },
  }), env);
  return res.status;
}

function faxForm(to: string, pages: number) {
  const form = new FormData();
  form.set("to", to);
  form.set("pages", String(pages));
  form.set("file", new File([new Uint8Array([37, 80, 68, 70])], "fax.pdf", { type: "application/pdf" }));
  return form;
}

describe("Faxlane API", () => {
  it("registers a guest with 3 free pages", async () => {
    expect((await call("GET", "/v1/me")).status).toBe(401);
    const res = await call("POST", "/v1/accounts", { token: TOKEN }, false);
    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({ plan: null, pagesLeft: 3, signedIn: false });
    const again = await call("POST", "/v1/accounts", { token: TOKEN }, false);
    expect(again.body.id).toBe(res.body.id);
  });

  it("sends a fax from the shared number and charges pages", async () => {
    const res = await call("POST", "/v1/faxes", faxForm("(555) 013-4470", 2));
    expect(res.status).toBe(201);
    expect(res.body).toMatchObject({ state: "queued", cost: 2, number: "+15550134470" });
    expect(telnyxSent[0]).toMatchObject({ to: "+15550134470", from: "+15550000000", connection_id: "fax-app-1" });
    expect((telnyxSent[0] as { media_url: string }).media_url).toContain("/v1/media/");
    expect((await call("GET", "/v1/me")).body.pagesLeft).toBe(1);

    expect(await telnyxEvent("fax.sending.started", { fax_id: "tx-1" })).toBe(200);
    expect((await call("GET", "/v1/faxes?folder=outbox")).body.faxes[0].state).toBe("sending");

    // Telnyx reports the real count: 1 page, so 1 page comes back.
    expect(await telnyxEvent("fax.delivered", { fax_id: "tx-1", page_count: 1 })).toBe(200);
    const sent = (await call("GET", "/v1/faxes?folder=sent")).body.faxes;
    expect(sent[0]).toMatchObject({ state: "delivered", pages: 1, cost: 1 });
    expect((await call("GET", "/v1/me")).body.pagesLeft).toBe(2);
  });

  it("gives every page back when a fax fails", async () => {
    await call("POST", "/v1/faxes", faxForm("+1 555 019 2208", 2));
    expect((await call("GET", "/v1/me")).body.pagesLeft).toBe(0);
    await telnyxEvent("fax.failed", { fax_id: "tx-2", failure_reason: "user_busy" });
    const sent = (await call("GET", "/v1/faxes?folder=sent")).body.faxes;
    expect(sent.find((f: any) => f.state === "failed").failureReason).toMatch(/busy/);
    expect((await call("GET", "/v1/me")).body.pagesLeft).toBe(2);
  });

  it("refuses unsafe or unaffordable destinations", async () => {
    expect((await call("POST", "/v1/faxes", faxForm("+1 900 555 1234", 1))).body.error).toBe("destination_not_supported");
    expect((await call("POST", "/v1/faxes", faxForm("+7 916 123 4567", 1))).body.error).toBe("destination_not_supported");
    // International pages count 3×: 1 page = 3 > 2 left.
    expect((await call("POST", "/v1/faxes", faxForm("+44 20 7946 0958", 1))).status).toBe(402);
  });

  it("rejects webhooks with a bad signature", async () => {
    const res = await worker.fetch(new Request("https://api.faxlane.test/v1/webhooks/telnyx", {
      method: "POST", body: "{}", headers: { "telnyx-signature-ed25519": "AAAA", "telnyx-timestamp": String(Math.floor(Date.now() / 1000)) },
    }), env);
    expect(res.status).toBe(401);
  });

  it("activates a plan that RevenueCat confirms", async () => {
    // The app's claim alone changes nothing: RevenueCat has no purchase yet.
    expect((await call("POST", "/v1/purchases")).body.plan).toBeNull();
    rcSubscriber.subscriptions["com.faxlane.premium.monthly"] = { expires_date: iso(30 * 86400_000), purchase_date: iso(0), store: "app_store" };
    const res = await call("POST", "/v1/purchases");
    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({ plan: "premium", period: "monthly", pageLimit: 300, pagesLeft: 300 });
  });

  it("rejects RevenueCat webhooks without the shared secret", async () => {
    const me = (await call("GET", "/v1/me")).body;
    expect(await revenueCatEvent({ type: "EXPIRATION", app_user_id: me.id }, "wrong")).toBe(401);
    expect((await call("GET", "/v1/me")).body.plan).toBe("premium");
  });

  it("receives faxes, drops blocked senders and locks faxes when pages run out", async () => {
    const me = (await call("GET", "/v1/me")).body;
    d1.raw.prepare("INSERT INTO numbers (e164, account_id, created_at) VALUES (?, ?, ?)").run("+15550142290", me.id, 0);

    await telnyxEvent("fax.received", { fax_id: "in-1", from: "+15550134470", to: "+15550142290", page_count: 2, media_url: "https://media.telnyx.test/in.pdf" });
    let inbox = (await call("GET", "/v1/faxes?folder=inbox")).body.faxes;
    expect(inbox[0]).toMatchObject({ state: "received", pages: 2, unread: true });
    expect((await call("GET", "/v1/me")).body.pagesLeft).toBe(298);
    const pdf = await call("GET", `/v1/faxes/${inbox[0].id}/pdf`);
    expect(pdf.status).toBe(200);

    // Same event twice is ignored.
    await telnyxEvent("fax.received", { fax_id: "in-1", from: "+15550134470", to: "+15550142290", page_count: 2, media_url: "https://media.telnyx.test/in.pdf" });
    expect((await call("GET", "/v1/faxes?folder=inbox")).body.faxes).toHaveLength(1);

    await call("POST", "/v1/blocked", { number: "+1 555 010 8841" });
    await telnyxEvent("fax.received", { fax_id: "in-2", from: "+15550108841", to: "+15550142290", page_count: 5, media_url: "https://media.telnyx.test/in.pdf" });
    expect((await call("GET", "/v1/faxes?folder=inbox")).body.faxes).toHaveLength(1);
    expect((await call("GET", "/v1/me")).body.pagesLeft).toBe(298);

    d1.raw.prepare("UPDATE accounts SET pages_used = 300").run();
    await telnyxEvent("fax.received", { fax_id: "in-3", from: "+15550192208", to: "+15550142290", page_count: 3, media_url: "https://media.telnyx.test/in.pdf" });
    inbox = (await call("GET", "/v1/faxes?folder=inbox")).body.faxes;
    const locked = inbox.find((f: any) => f.state === "locked");
    expect(locked).toBeTruthy();
    expect((await call("GET", `/v1/faxes/${locked.id}/pdf`)).status).toBe(402);

    // Buy a 10-page pack, then open the locked fax.
    rcSubscriber.non_subscriptions["com.faxlane.pages.10"] = [{ id: "rc-2001", store_transaction_id: "2001", purchase_date: iso(0), store: "app_store" }];
    expect((await call("POST", "/v1/purchases")).body.extraPages).toBe(10);
    expect((await call("POST", "/v1/purchases")).body.extraPages).toBe(10); // no double credit
    expect((await call("POST", `/v1/faxes/${locked.id}/unlock`)).body.state).toBe("received");
    expect((await call("GET", "/v1/me")).body.extraPages).toBe(7);
  });

  it("takes page-pack pages back after a refund", async () => {
    const me = (await call("GET", "/v1/me")).body;
    const refund = { type: "CANCELLATION", cancel_reason: "CUSTOMER_SUPPORT", app_user_id: me.id, product_id: "com.faxlane.pages.10", transaction_id: "2001" };
    expect(await revenueCatEvent(refund)).toBe(200);
    expect((await call("GET", "/v1/me")).body.extraPages).toBe(-3);
    await revenueCatEvent(refund); // only once
    expect((await call("GET", "/v1/me")).body.extraPages).toBe(-3);
  });

  it("holds numbers for 14 days when the plan ends", async () => {
    const me = (await call("GET", "/v1/me")).body;
    rcSubscriber.subscriptions["com.faxlane.premium.monthly"] = { expires_date: iso(-1000), purchase_date: iso(-31 * 86400_000), store: "app_store" };
    expect(await revenueCatEvent({ type: "EXPIRATION", app_user_id: me.id, product_id: "com.faxlane.premium.monthly" })).toBe(200);
    expect((await call("GET", "/v1/me")).body.plan).toBeNull();
    const row = d1.raw.prepare("SELECT release_after FROM numbers").get() as { release_after: number };
    expect(row.release_after).toBeGreaterThan(Math.floor(Date.now() / 1000) + 13 * 86400);
  });

  it("serves outgoing PDFs to Telnyx only with a valid signed link", async () => {
    const fax = d1.raw.prepare("SELECT id FROM faxes WHERE direction = 'sent' LIMIT 1").get() as { id: string };
    const good = new URL(await signedMediaUrl(env.PUBLIC_BASE_URL, env.MEDIA_SIGNING_SECRET, fax.id));
    expect((await worker.fetch(new Request(good), env)).status).toBe(200);
    good.searchParams.set("sig", "tampered");
    expect((await worker.fetch(new Request(good), env)).status).toBe(403);
  });

  it("resets page cycles in the daily job", async () => {
    d1.raw.prepare("UPDATE accounts SET plan = 'basic', period = 'monthly', pages_used = 80, cycle_start = ?").run(Math.floor(Date.now() / 1000) - 31 * 86400);
    await runDaily(env);
    expect((await call("GET", "/v1/me")).body.pagesUsed).toBe(0);
  });

  it("deletes the account and every file", async () => {
    vi.stubGlobal("fetch", async (input: RequestInfo | URL) => {
      const url = String(input);
      if (url.includes("/phone_numbers?")) return Response.json({ data: [{ id: "pn-1" }] });
      if (url.endsWith("/phone_numbers/pn-1")) return Response.json({});
      throw new Error(`Unexpected fetch ${url}`);
    });
    expect((await call("DELETE", "/v1/me")).status).toBe(200);
    expect(r2.store.size).toBe(0);
    expect((await call("GET", "/v1/me")).status).toBe(401);
  });
});
