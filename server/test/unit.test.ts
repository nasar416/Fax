import { describe, expect, it } from "vitest";
import { pageLimit, pagesLeft, parseProductId, splitCharge } from "../src/plans";
import { countPdfPages, isAllowedCountry, isBlockedDestination, pageMultiplier, toE164 } from "../src/phone";
import { hmacSign, signedMediaUrl, verifyMediaSignature, verifyTelnyxSignature, bytesToBase64Url } from "../src/crypto";
import { HttpError, Router, json } from "../src/http";

describe("plans", () => {
  it("has the page limits the app shows", () => {
    expect(pageLimit("basic", "weekly")).toBe(25);
    expect(pageLimit("premium", "weekly")).toBe(75);
    expect(pageLimit("basic", "annual")).toBe(100);
    expect(pageLimit("premium", "monthly")).toBe(300);
    expect(pageLimit("business", "annual")).toBe(700);
    expect(pageLimit("enterprise", "monthly")).toBe(2000);
  });

  it("parses App Store product IDs", () => {
    expect(parseProductId("com.faxlane.premium.annual")).toEqual({ kind: "subscription", plan: "premium", period: "annual" });
    expect(parseProductId("com.faxlane.pages.25")).toEqual({ kind: "pages", pages: 25 });
    expect(parseProductId("com.faxlane.business.weekly")).toBeNull();
    expect(parseProductId("com.faxlane.pages.7")).toBeNull();
    expect(parseProductId("com.other.premium.annual")).toBeNull();
  });

  it("spends free pages, then page packs", () => {
    const free = { plan: null, period: null, pagesUsed: 0, extraPages: 10, freePagesLeft: 3 };
    expect(splitCharge(free, 5)).toEqual({ fromPlan: 0, fromExtra: 2, fromFree: 3 });
    expect(splitCharge(free, 14)).toBeNull();
    expect(pagesLeft(free)).toBe(13);
  });

  it("spends plan pages, then page packs", () => {
    const paid = { plan: "basic" as const, period: "monthly" as const, pagesUsed: 98, extraPages: 5, freePagesLeft: 0 };
    expect(splitCharge(paid, 4)).toEqual({ fromPlan: 2, fromExtra: 2, fromFree: 0 });
    expect(splitCharge(paid, 8)).toBeNull();
    expect(pagesLeft({ ...paid, extraPages: -3 })).toBe(2);
  });
});

describe("phone", () => {
  it("normalises numbers", () => {
    expect(toE164("(555) 013-4470")).toBe("+15550134470");
    expect(toE164("+44 20 7946 0958")).toBe("+442079460958");
    expect(toE164("0044 20 7946 0958")).toBe("+442079460958");
    expect(toE164("12")).toBeNull();
  });
  it("counts international pages 3x and blocks premium numbers", () => {
    expect(pageMultiplier("+15550134470")).toBe(1);
    expect(pageMultiplier("+442079460958")).toBe(3);
    expect(isBlockedDestination("+19005551234")).toBe(true);
    expect(isAllowedCountry("+442079460958", "1,44")).toBe(true);
    expect(isAllowedCountry("+79161234567", "1,44")).toBe(false);
  });
});

describe("crypto", () => {
  it("signs media links that expire and can't be altered", async () => {
    const url = new URL(await signedMediaUrl("https://api.example", "secret", "fax-1"));
    const exp = url.searchParams.get("exp");
    const sig = url.searchParams.get("sig");
    expect(await verifyMediaSignature("secret", "fax-1", exp, sig)).toBe(true);
    expect(await verifyMediaSignature("secret", "fax-2", exp, sig)).toBe(false);
    expect(await verifyMediaSignature("other", "fax-1", exp, sig)).toBe(false);
    const past = String(Math.floor(Date.now() / 1000) - 10);
    expect(await verifyMediaSignature("secret", "fax-1", past, await hmacSign("secret", `fax-1.${past}`))).toBe(false);
  });

  it("verifies Telnyx Ed25519 webhook signatures", async () => {
    const pair = (await crypto.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"])) as CryptoKeyPair;
    const pub = btoa(String.fromCharCode(...new Uint8Array(await crypto.subtle.exportKey("raw", pair.publicKey) as ArrayBuffer)));
    const body = '{"data":{}}';
    const sig = new Uint8Array(await crypto.subtle.sign("Ed25519", pair.privateKey, new TextEncoder().encode(`123|${body}`)));
    const sigB64 = btoa(String.fromCharCode(...sig));
    expect(await verifyTelnyxSignature(pub, "123", body, sigB64)).toBe(true);
    expect(await verifyTelnyxSignature(pub, "124", body, sigB64)).toBe(false);
    expect(bytesToBase64Url(new Uint8Array([251, 255]))).toBe("-_8");
  });
});

describe("router", () => {
  it("matches params and reports 404/405", async () => {
    const r = new Router().on("GET", "/v1/faxes/:id", async (_req, p) => json({ id: p.id }));
    const res = await r.handle(new Request("https://x/v1/faxes/abc"));
    expect(await res.json()).toEqual({ id: "abc" });
    await expect(r.handle(new Request("https://x/v1/nope"))).rejects.toBeInstanceOf(HttpError);
    await expect(r.handle(new Request("https://x/v1/faxes/abc", { method: "DELETE" }))).rejects.toMatchObject({ status: 405 });
  });
});

describe("toll-fraud and cost protection", () => {
  it("treats Caribbean +1 numbers as foreign and blocks them", () => {
    expect(isBlockedDestination("+18765550123")).toBe(true); // Jamaica
    expect(isBlockedDestination("+18095550123")).toBe(true); // Dominican Republic
    expect(isBlockedDestination("+15005550123")).toBe(true); // personal 5XX
    expect(isBlockedDestination("+12125550123")).toBe(false); // New York
    expect(isBlockedDestination("+17875550123")).toBe(false); // Puerto Rico (US)
  });
  it("counts pages by destination cost", () => {
    expect(pageMultiplier("+12125550123")).toBe(1);
    expect(pageMultiplier("+442079460958")).toBe(3);
    expect(pageMultiplier("+97145550123")).toBe(10);
    expect(pageMultiplier("+8801711000000")).toBe(10);
  });
  it("counts PDF pages without trusting the app", () => {
    const pdf = new TextEncoder().encode("%PDF-1.4 1 0 obj << /Type /Pages /Count 2 >> 2 0 obj << /Type /Page >> 3 0 obj <</Type/Page>>").buffer;
    expect(countPdfPages(pdf)).toBe(2);
  });
});
