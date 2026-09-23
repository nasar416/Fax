import { DurableObject } from "cloudflare:workers";
import schema from "../schema.sql";

/**
 * The small part of the D1 API the server uses. The database itself is SQLite inside a
 * Durable Object (one instance, "main"), so it runs on the free Workers plan with no D1 needed.
 */
export interface Statement {
  bind(...values: unknown[]): Statement;
  first<T = Record<string, unknown>>(): Promise<T | null>;
  all<T = Record<string, unknown>>(): Promise<{ results: T[] }>;
  run(): Promise<{ meta: { changes: number } }>;
}
export interface Db {
  prepare(sql: string): Statement;
  batch(statements: Statement[]): Promise<{ meta: { changes: number } }[]>;
}

type Query = { sql: string; params: (string | number | null)[] };
type Mode = "first" | "all" | "run";

/** Holds the SQLite database. Every query runs here, one at a time, so writes are atomic. */
export class Database extends DurableObject {
  private sql: SqlStorage;

  constructor(ctx: DurableObjectState, env: unknown) {
    super(ctx, env as never);
    this.sql = ctx.storage.sql;
    this.sql.exec(schema); // CREATE TABLE IF NOT EXISTS: safe on every start
    // Columns added after the first deploy. Adding one that exists throws, which is fine.
    for (const change of ["ALTER TABLE accounts ADD COLUMN in_trial INTEGER NOT NULL DEFAULT 0"]) {
      try { this.sql.exec(change); } catch { /* already there */ }
    }
  }

  private exec(q: Query, mode: Mode): unknown {
    const rows = this.sql.exec(q.sql, ...q.params).toArray();
    if (mode === "first") return rows[0] ?? null;
    if (mode === "all") return { results: rows };
    const changes = Number(this.sql.exec("SELECT changes() AS c").one().c);
    return { meta: { changes } };
  }

  query(q: Query, mode: Mode): unknown {
    return this.exec(q, mode);
  }

  /** All statements succeed together or none do, like D1's batch. */
  batch(queries: Query[]): unknown[] {
    return this.ctx.storage.transactionSync(() => queries.map((q) => this.exec(q, "run")));
  }
}

class RemoteStatement implements Statement {
  constructor(private stub: DurableObjectStub<Database>, readonly sql: string, readonly params: (string | number | null)[] = []) {}
  bind(...values: unknown[]): Statement {
    return new RemoteStatement(this.stub, this.sql, values.map((v) => (v === undefined ? null : (v as string | number | null))));
  }
  async first<T>(): Promise<T | null> { return (await this.stub.query({ sql: this.sql, params: this.params }, "first")) as T | null; }
  async all<T>(): Promise<{ results: T[] }> { return (await this.stub.query({ sql: this.sql, params: this.params }, "all")) as { results: T[] }; }
  async run(): Promise<{ meta: { changes: number } }> { return (await this.stub.query({ sql: this.sql, params: this.params }, "run")) as { meta: { changes: number } }; }
}

export function openDatabase(ns: DurableObjectNamespace<Database>): Db {
  const stub = ns.get(ns.idFromName("main"));
  return {
    prepare: (sql) => new RemoteStatement(stub, sql),
    batch: async (statements) => (await stub.batch(statements.map((s) => {
      const r = s as RemoteStatement;
      return { sql: r.sql, params: r.params };
    }))) as { meta: { changes: number } }[],
  };
}
