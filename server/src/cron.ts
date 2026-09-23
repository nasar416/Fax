import type { Env } from "./env";
import { now } from "./http";
import { cycleSeconds, type Period } from "./plans";
import { releaseNumber } from "./telnyx";

/** Daily housekeeping. */
export async function runDaily(env: Env): Promise<void> {
  const ts = now();

  // 1. New page cycle for active plans (weekly plans every 7 days, others every 30 days).
  const { results: due } = await env.DB.prepare("SELECT id, period, cycle_start FROM accounts WHERE plan IS NOT NULL")
    .all<{ id: string; period: Period; cycle_start: number }>();
  for (const a of due) {
    const length = cycleSeconds(a.period);
    if (ts - a.cycle_start >= length) {
      const cycles = Math.floor((ts - a.cycle_start) / length);
      await env.DB.prepare("UPDATE accounts SET pages_used = 0, cycle_start = ? WHERE id = ?").bind(a.cycle_start + cycles * length, a.id).run();
    }
  }

  // 2. Retention: erase faxes older than each account's setting, and Trash older than 30 days.
  const { results: old } = await env.DB.prepare(
    `SELECT f.id, f.r2_key FROM faxes f JOIN accounts a ON a.id = f.account_id
     WHERE f.created_at < ? - a.retention_days * 86400 OR (f.deleted_at IS NOT NULL AND f.deleted_at < ?)
     LIMIT 1000`,
  ).bind(ts, ts - 30 * 86400).all<{ id: string; r2_key: string | null }>();
  const keys = old.map((f) => f.r2_key).filter((k): k is string => !!k);
  if (keys.length) await env.FAXES.delete(keys);
  for (const f of old) await env.DB.prepare("DELETE FROM faxes WHERE id = ?").bind(f.id).run();

  // 3. Release numbers whose 14-day hold is over, so they stop costing money.
  const { results: expired } = await env.DB.prepare("SELECT e164 FROM numbers WHERE release_after IS NOT NULL AND release_after < ?")
    .bind(ts).all<{ e164: string }>();
  for (const n of expired) {
    try {
      await releaseNumber(env, n.e164);
      await env.DB.prepare("DELETE FROM numbers WHERE e164 = ?").bind(n.e164).run();
    } catch (err) {
      console.error("Number release failed", n.e164, err);
    }
  }
}
