export type Plan = "basic" | "premium" | "business" | "enterprise";
export type Period = "weekly" | "monthly" | "annual";

const PLANS: Plan[] = ["basic", "premium", "business", "enterprise"];
const PERIODS: Period[] = ["weekly", "monthly", "annual"];

/** Pages per cycle. Sent and received pages both count. Must match PlanTier in the iOS app. */
export function pageLimit(plan: Plan, period: Period): number {
  if (period === "weekly") return plan === "basic" ? 25 : plan === "premium" ? 75 : pageLimit(plan, "monthly");
  return { basic: 100, premium: 300, business: 700, enterprise: 2000 }[plan];
}

export function numbersIncluded(plan: Plan | null): number {
  if (!plan) return 0;
  return { basic: 1, premium: 1, business: 2, enterprise: 5 }[plan];
}

export function teamSeats(plan: Plan | null): number {
  if (!plan) return 1;
  return { basic: 1, premium: 1, business: 5, enterprise: 20 }[plan];
}

/** Length of one page cycle in seconds: weekly plans reset weekly, everything else every 30 days. */
export function cycleSeconds(period: Period | null): number {
  return (period === "weekly" ? 7 : 30) * 24 * 3600;
}

export type Product =
  | { kind: "subscription"; plan: Plan; period: Period }
  | { kind: "pages"; pages: number };

/** Parses App Store product IDs: com.faxlane.<plan>.<period> or com.faxlane.pages.<n>. */
export function parseProductId(id: string): Product | null {
  const parts = id.split(".");
  if (parts.length !== 4 || parts[0] !== "com" || parts[1] !== "faxlane") return null;
  const [, , a, b] = parts as [string, string, string, string];
  if (a === "pages") {
    const pages = Number(b);
    return [10, 25, 50].includes(pages) ? { kind: "pages", pages } : null;
  }
  if (PLANS.includes(a as Plan) && PERIODS.includes(b as Period)) {
    if ((a === "business" || a === "enterprise") && b === "weekly") return null;
    return { kind: "subscription", plan: a as Plan, period: b as Period };
  }
  return null;
}

/** During a free trial only this many plan pages can be used (stops trial farming). */
export const TRIAL_PAGES = 10;

export interface Balance {
  plan: Plan | null;
  period: Period | null;
  pagesUsed: number;
  extraPages: number;
  freePagesLeft: number;
  inTrial?: boolean;
}

/** The plan's page allowance, capped while in a free trial. */
export function planLimit(b: Balance): number {
  if (!b.plan || !b.period) return 0;
  const limit = pageLimit(b.plan, b.period);
  return b.inTrial ? Math.min(limit, TRIAL_PAGES) : limit;
}

export function pagesLeft(b: Balance): number {
  if (!b.plan || !b.period) return b.freePagesLeft + Math.max(b.extraPages, 0);
  return Math.max(planLimit(b) - b.pagesUsed, 0) + Math.max(b.extraPages, 0);
}

export interface Charge {
  fromPlan: number;
  fromExtra: number;
  fromFree: number;
}

/**
 * Splits a page cost across plan pages, page packs and free pages.
 * Returns null when the account doesn't have enough pages.
 */
export function splitCharge(b: Balance, cost: number): Charge | null {
  if (cost <= 0) return { fromPlan: 0, fromExtra: 0, fromFree: 0 };
  if (!b.plan || !b.period) {
    const fromFree = Math.min(cost, b.freePagesLeft);
    const fromExtra = cost - fromFree;
    if (fromExtra > Math.max(b.extraPages, 0)) return null;
    return { fromPlan: 0, fromExtra, fromFree };
  }
  const planLeft = Math.max(planLimit(b) - b.pagesUsed, 0);
  const fromPlan = Math.min(cost, planLeft);
  const fromExtra = cost - fromPlan;
  if (fromExtra > Math.max(b.extraPages, 0)) return null;
  return { fromPlan, fromExtra, fromFree: 0 };
}
