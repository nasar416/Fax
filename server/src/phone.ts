/**
 * Counts pages in a PDF by its page objects. The app's own page count is never trusted alone:
 * the larger of the two is charged, so a 50-page PDF can't be sent for the price of one.
 * Returns 0 if the PDF hides its pages (compressed object streams); Telnyx's real count then
 * settles it after delivery.
 */
export function countPdfPages(bytes: ArrayBuffer): number {
  const text = new TextDecoder("latin1").decode(bytes);
  return (text.match(/\/Type\s*\/Page(?![a-zA-Z])/g) ?? []).length;
}

/** Normalises user input to E.164 (+15550134470). Returns null if it can't be a fax number. */
export function toE164(input: string): string | null {
  const trimmed = input.trim();
  const digits = trimmed.replace(/[^\d]/g, "");
  if (digits.length < 8 || digits.length > 15) return null;
  if (trimmed.startsWith("+")) return `+${digits}`;
  if (trimmed.startsWith("00")) return `+${digits.slice(2)}`;
  if (digits.length === 10) return `+1${digits}`; // US/Canada without country code
  if (digits.length === 11 && digits.startsWith("1")) return `+${digits}`;
  return null;
}

/**
 * +1 area codes that are NOT the US or Canada (Caribbean and other NANP countries).
 * They look domestic but cost international rates, so they are a classic toll-fraud route.
 */
const NANP_FOREIGN = new Set([
  "242", "246", "264", "268", "284", "345", "441", "473", "649", "658", "664", "721", "758", "767",
  "784", "809", "829", "849", "868", "869", "876",
]);

/** Premium-rate, personal and special +1 area codes we never dial. */
const NANP_BLOCKED = new Set([
  "900", "976", "700", "710", "500", "521", "522", "523", "524", "525", "526", "527", "528", "529", "532", "533",
  "535", "538", "542", "543", "544", "545", "546", "547", "549", "550", "552", "553", "554", "556", "566", "569",
  "577", "578", "588", "589",
]);

/** US, Canada and US territories (Puerto Rico, USVI, Guam, N. Mariana Is., American Samoa). */
export function isDomestic(e164: string): boolean {
  return e164.startsWith("+1") && e164.length === 12 && !NANP_FOREIGN.has(e164.slice(2, 5));
}

/**
 * Countries whose landline fax rates are close to Western Europe. Every other allowed country
 * costs much more per minute, so its pages count 10×. This keeps even the cheapest plan page
 * (Enterprise annual, after Apple's cut and VAT) above what Telnyx charges.
 */
const LOW_COST_CODES = ["44", "353", "49", "33", "39", "34", "31", "32", "41", "43", "45", "46", "47", "358", "351", "48", "420", "61", "64", "81", "82", "852", "65", "972"];

/** Pages count 1× in the US/Canada, 3× in low-cost countries, 10× elsewhere. */
export function pageMultiplier(e164: string): number {
  if (isDomestic(e164)) return 1;
  const digits = e164.slice(1);
  return LOW_COST_CODES.some((code) => digits.startsWith(code)) ? 3 : 10;
}

/** Premium-rate and other risky ranges we never dial (toll-fraud protection). */
export function isBlockedDestination(e164: string): boolean {
  if (e164.startsWith("+1")) {
    if (e164.length !== 12) return true;
    const area = e164.slice(2, 5);
    return NANP_BLOCKED.has(area) || NANP_FOREIGN.has(area);
  }
  return false;
}

export function isAllowedCountry(e164: string, allowedCsv: string): boolean {
  const codes = allowedCsv.split(",").map((c) => c.trim()).filter(Boolean);
  const digits = e164.slice(1);
  return codes.some((code) => digits.startsWith(code));
}
