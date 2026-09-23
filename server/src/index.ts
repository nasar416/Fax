import type { Env } from "./env";
import { runDaily } from "./cron";
import { errorResponse, json, Router } from "./http";
import { accountRoutes } from "./routes/account";
import { faxRoutes } from "./routes/faxes";
import { miscRoutes } from "./routes/misc";
import { purchaseRoutes } from "./routes/purchases";
import { webhookRoutes } from "./routes/webhooks";

export function buildRouter(env: Env): Router {
  const router = new Router();
  router.on("GET", "/", async () => json({ service: "faxlane-api", ok: true }));
  accountRoutes(router, env);
  faxRoutes(router, env);
  purchaseRoutes(router, env);
  webhookRoutes(router, env);
  miscRoutes(router, env);
  return router;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try {
      return await buildRouter(env).handle(request);
    } catch (err) {
      return errorResponse(err);
    }
  },

  async scheduled(_event: ScheduledController, env: Env, ctx: ExecutionContext): Promise<void> {
    ctx.waitUntil(runDaily(env));
  },
} satisfies ExportedHandler<Env>;
