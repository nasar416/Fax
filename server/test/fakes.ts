// In-memory stand-ins for Cloudflare D1 and R2, backed by Node's built-in SQLite.
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";

// Loaded with require so Vite doesn't try to bundle the built-in module.
const { DatabaseSync } = createRequire(import.meta.url)("node:sqlite") as typeof import("node:sqlite");
type DatabaseSync = InstanceType<typeof DatabaseSync>;

type Value = string | number | null;

class FakeStatement {
  constructor(private db: DatabaseSync, private sql: string, private params: Value[] = []) {}
  bind(...params: Value[]) {
    for (const p of params) if (p === undefined) throw new Error(`undefined bound in: ${this.sql}`);
    return new FakeStatement(this.db, this.sql, params);
  }
  async first<T>(): Promise<T | null> {
    return (this.db.prepare(this.sql).get(...this.params) as T | undefined) ?? null;
  }
  async all<T>(): Promise<{ results: T[] }> {
    return { results: this.db.prepare(this.sql).all(...this.params) as T[] };
  }
  async run() {
    const r = this.db.prepare(this.sql).run(...this.params);
    return { meta: { changes: Number(r.changes) } };
  }
  runSync() {
    return this.db.prepare(this.sql).run(...this.params);
  }
}

export function fakeD1() {
  const db = new DatabaseSync(":memory:");
  db.exec("PRAGMA foreign_keys = ON;");
  db.exec(readFileSync(new URL("../schema.sql", import.meta.url), "utf8"));
  return {
    raw: db,
    prepare: (sql: string) => new FakeStatement(db, sql),
    async batch(statements: FakeStatement[]) {
      db.exec("BEGIN");
      try {
        const out = statements.map((s) => ({ meta: { changes: Number(s.runSync().changes) } }));
        db.exec("COMMIT");
        return out;
      } catch (e) {
        db.exec("ROLLBACK");
        throw e;
      }
    },
  };
}

export function fakeR2() {
  const store = new Map<string, ArrayBuffer>();
  return {
    store,
    async put(key: string, value: ArrayBuffer) { store.set(key, value); },
    async get(key: string) { const v = store.get(key); return v ? { body: v } : null; },
    async delete(keys: string | string[]) { for (const k of Array.isArray(keys) ? keys : [keys]) store.delete(k); },
  };
}
