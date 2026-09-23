// Stand-in for the "cloudflare:workers" module, which only exists inside the Workers runtime.
export class DurableObject {
  constructor(public ctx: unknown, public env: unknown) {}
}
