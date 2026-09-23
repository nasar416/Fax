import type { Env } from "./env";
import { HttpError } from "./http";

const API = "https://api.telnyx.com/v2";

async function call<T>(env: Env, path: string, init: RequestInit = {}): Promise<T> {
  const res = await fetch(`${API}${path}`, {
    ...init,
    headers: {
      authorization: `Bearer ${env.TELNYX_API_KEY}`,
      "content-type": "application/json",
      accept: "application/json",
      ...(init.headers ?? {}),
    },
  });
  const text = await res.text();
  if (!res.ok) {
    console.error("Telnyx error", res.status, path, text.slice(0, 500));
    throw new HttpError(502, "fax_provider_error", "The fax network is not available right now. Try again in a moment.");
  }
  return (text ? JSON.parse(text) : {}) as T;
}

/** Sends a fax. Telnyx downloads the PDF from `mediaUrl`. */
export async function sendFax(env: Env, opts: { to: string; from: string; mediaUrl: string }): Promise<string> {
  const body = {
    connection_id: env.TELNYX_FAX_APP_ID,
    media_url: opts.mediaUrl,
    to: opts.to,
    from: opts.from,
    quality: "high",
    store_media: false,
  };
  const res = await call<{ data: { id: string } }>(env, "/faxes", { method: "POST", body: JSON.stringify(body) });
  return res.data.id;
}

export interface AvailableNumber {
  phone_number: string;
  region_information?: { region_name?: string; region_type?: string }[];
}

export async function searchNumbers(env: Env, country: string, areaCode?: string): Promise<AvailableNumber[]> {
  const params = new URLSearchParams({
    "filter[country_code]": country,
    "filter[features][]": "fax",
    "filter[limit]": "10",
  });
  if (areaCode) params.set("filter[national_destination_code]", areaCode);
  const res = await call<{ data: AvailableNumber[] }>(env, `/available_phone_numbers?${params}`);
  return res.data;
}

/** Orders a number and attaches it to the Faxlane fax application. */
export async function orderNumber(env: Env, e164: string): Promise<string> {
  const res = await call<{ data: { id: string } }>(env, "/number_orders", {
    method: "POST",
    body: JSON.stringify({ phone_numbers: [{ phone_number: e164 }], connection_id: env.TELNYX_FAX_APP_ID }),
  });
  return res.data.id;
}

/** Releases a number back to Telnyx so it stops costing money. */
export async function releaseNumber(env: Env, e164: string): Promise<void> {
  const params = new URLSearchParams({ "filter[phone_number]": e164 });
  const found = await call<{ data: { id: string }[] }>(env, `/phone_numbers?${params}`);
  const id = found.data[0]?.id;
  if (id) await call(env, `/phone_numbers/${id}`, { method: "DELETE" });
}

/** Downloads a received fax PDF (Telnyx media links are temporary). */
export async function downloadMedia(url: string): Promise<ArrayBuffer> {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`Media download failed: ${res.status}`);
  return res.arrayBuffer();
}
