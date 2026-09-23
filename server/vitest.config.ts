import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { defineConfig } from "vitest/config";

export default defineConfig({
  test: { environment: "node", include: ["test/**/*.test.ts"] },
  resolve: { alias: { "cloudflare:workers": fileURLToPath(new URL("./test/cloudflare-workers.ts", import.meta.url)) } },
  plugins: [{
    name: "sql-as-text", // matches wrangler's Text rule for *.sql
    load(id) { return id.endsWith(".sql") ? `export default ${JSON.stringify(readFileSync(id, "utf8"))};` : null; },
  }],
});
