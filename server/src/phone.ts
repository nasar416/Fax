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

/** North American Numbering Plan (US, Canada) counts as domestic. */
export function isDomestic(e164: string): boolean {
  return e164.startsWith("+1") && e164.length === 12;
}

/** International pages count 3×. */
export function pageMultiplier(e164: string): number {
  return isDomestic(e164) ? 1 : 3;
}

/** Premium-rate and other risky ranges we never dial (toll-fraud protection). */
export function isBlockedDestination(e164: string): boolean {
  if (isDomestic(e164)) {
    const area = e164.slice(2, 5);
    return ["900", "976"].includes(area);
  }
  return false;
}

export function isAllowedCountry(e164: string, allowedCsv: string): boolean {
  const codes = allowedCsv.split(",").map((c) => c.trim()).filter(Boolean);
  const digits = e164.slice(1);
  return codes.some((code) => digits.startsWith(code));
}
