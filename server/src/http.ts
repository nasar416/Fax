export class HttpError extends Error {
  constructor(public status: number, public code: string, message?: string) {
    super(message ?? code);
  }
}

export function json(data: unknown, status = 200, headers: HeadersInit = {}): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", ...headers },
  });
}

export function errorResponse(err: unknown): Response {
  if (err instanceof HttpError) {
    return json({ error: err.code, message: err.message }, err.status);
  }
  console.error("Unhandled error", err);
  return json({ error: "internal_error", message: "Something went wrong." }, 500);
}

export async function readJson<T>(request: Request): Promise<T> {
  try {
    return (await request.json()) as T;
  } catch {
    throw new HttpError(400, "invalid_json", "The request body must be JSON.");
  }
}

type Handler = (request: Request, params: Record<string, string>) => Promise<Response>;

/** Tiny path router: "/v1/faxes/:id" style patterns. */
export class Router {
  private routes: { method: string; pattern: RegExp; keys: string[]; handler: Handler }[] = [];

  on(method: string, path: string, handler: Handler): this {
    const keys: string[] = [];
    const pattern = new RegExp(
      "^" +
        path.replace(/:([a-zA-Z]+)/g, (_, key: string) => {
          keys.push(key);
          return "([^/]+)";
        }) +
        "/?$",
    );
    this.routes.push({ method, pattern, keys, handler });
    return this;
  }

  async handle(request: Request): Promise<Response> {
    const url = new URL(request.url);
    let pathMatched = false;
    for (const route of this.routes) {
      const match = route.pattern.exec(url.pathname);
      if (!match) continue;
      pathMatched = true;
      if (route.method !== request.method) continue;
      const params: Record<string, string> = {};
      route.keys.forEach((key, i) => (params[key] = decodeURIComponent(match[i + 1] ?? "")));
      return route.handler(request, params);
    }
    throw pathMatched ? new HttpError(405, "method_not_allowed") : new HttpError(404, "not_found");
  }
}

export const now = () => Math.floor(Date.now() / 1000);
