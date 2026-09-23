const encoder = new TextEncoder();

export function bytesToHex(bytes: ArrayBuffer | Uint8Array): string {
  return [...new Uint8Array(bytes)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export async function sha256Hex(text: string): Promise<string> {
  return bytesToHex(await crypto.subtle.digest("SHA-256", encoder.encode(text)));
}

export function base64ToBytes(b64: string): Uint8Array {
  const normalized = b64.replace(/-/g, "+").replace(/_/g, "/");
  const padded = normalized + "=".repeat((4 - (normalized.length % 4)) % 4);
  const bin = atob(padded);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

export function bytesToBase64Url(bytes: ArrayBuffer | Uint8Array): string {
  let bin = "";
  for (const b of new Uint8Array(bytes)) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export function base64UrlEncodeJson(value: unknown): string {
  return bytesToBase64Url(encoder.encode(JSON.stringify(value)));
}

/** Reads the payload of a JWS/JWT without verifying it. Only use on data fetched from a trusted source over TLS. */
export function decodeJwsPayload<T>(jws: string): T {
  const part = jws.split(".")[1];
  if (!part) throw new Error("Malformed JWS");
  return JSON.parse(new TextDecoder().decode(base64ToBytes(part))) as T;
}

export function decodeJwsHeader<T>(jws: string): T {
  const part = jws.split(".")[0];
  if (!part) throw new Error("Malformed JWS");
  return JSON.parse(new TextDecoder().decode(base64ToBytes(part))) as T;
}

async function hmacKey(secret: string): Promise<CryptoKey> {
  return crypto.subtle.importKey("raw", encoder.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign", "verify"]);
}

export async function hmacSign(secret: string, message: string): Promise<string> {
  const sig = await crypto.subtle.sign("HMAC", await hmacKey(secret), encoder.encode(message));
  return bytesToBase64Url(sig);
}

/** Constant-time check of an HMAC signature. */
export async function hmacVerify(secret: string, message: string, signature: string): Promise<boolean> {
  try {
    return await crypto.subtle.verify("HMAC", await hmacKey(secret), base64ToBytes(signature), encoder.encode(message));
  } catch {
    return false;
  }
}

/** Signed, expiring URL so Telnyx can fetch an outgoing PDF without an account token. */
export async function signedMediaUrl(baseUrl: string, secret: string, faxId: string, ttlSeconds = 3600): Promise<string> {
  const exp = Math.floor(Date.now() / 1000) + ttlSeconds;
  const sig = await hmacSign(secret, `${faxId}.${exp}`);
  return `${baseUrl.replace(/\/$/, "")}/v1/media/${faxId}?exp=${exp}&sig=${sig}`;
}

export async function verifyMediaSignature(secret: string, faxId: string, exp: string | null, sig: string | null): Promise<boolean> {
  if (!exp || !sig) return false;
  if (Number(exp) < Math.floor(Date.now() / 1000)) return false;
  return hmacVerify(secret, `${faxId}.${exp}`, sig);
}

/** Telnyx signs webhooks with Ed25519 over "timestamp|body". */
export async function verifyTelnyxSignature(publicKeyB64: string, timestamp: string, body: string, signatureB64: string): Promise<boolean> {
  try {
    const key = await crypto.subtle.importKey("raw", base64ToBytes(publicKeyB64), { name: "Ed25519" }, false, ["verify"]);
    return await crypto.subtle.verify("Ed25519", key, base64ToBytes(signatureB64), encoder.encode(`${timestamp}|${body}`));
  } catch {
    return false;
  }
}

/** Verifies a Sign in with Apple identity token (RS256) against Apple's public keys. */
export async function verifyAppleIdentityToken(token: string, bundleId: string, fetcher: typeof fetch = fetch): Promise<{ sub: string; email?: string }> {
  const [h, p, s] = token.split(".");
  if (!h || !p || !s) throw new Error("Malformed identity token");
  const header = decodeJwsHeader<{ kid: string; alg: string }>(token);
  if (header.alg !== "RS256") throw new Error("Unexpected algorithm");
  const res = await fetcher("https://appleid.apple.com/auth/keys");
  const { keys } = (await res.json()) as { keys: (JsonWebKey & { kid: string })[] };
  const jwk = keys.find((k) => k.kid === header.kid);
  if (!jwk) throw new Error("Unknown signing key");
  const key = await crypto.subtle.importKey("jwk", jwk, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["verify"]);
  const ok = await crypto.subtle.verify("RSASSA-PKCS1-v1_5", key, base64ToBytes(s), encoder.encode(`${h}.${p}`));
  if (!ok) throw new Error("Bad signature");
  const claims = decodeJwsPayload<{ iss: string; aud: string; exp: number; sub: string; email?: string }>(token);
  if (claims.iss !== "https://appleid.apple.com") throw new Error("Bad issuer");
  if (claims.aud !== bundleId) throw new Error("Bad audience");
  if (claims.exp < Math.floor(Date.now() / 1000)) throw new Error("Token expired");
  return { sub: claims.sub, email: claims.email };
}

export function randomId(): string {
  return crypto.randomUUID();
}
