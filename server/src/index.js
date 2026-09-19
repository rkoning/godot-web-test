import { assignName } from "./names.js";

const ROOM_NAME = "global";
const MAX_MESSAGE_BYTES = 512;
// A click is one request against the free tier, so cap what a single socket can
// spend. Well above what a human can click, well below what a loop can.
const MAX_CLICKS_PER_SECOND = 25;

export class Room {
  #buckets = new WeakMap();

  constructor(ctx, env) {
    this.ctx = ctx;
    this.env = env;
    // Answer raw "ping" frames without waking the object, so keepalives from
    // idle tabs don't hold it out of hibernation.
    this.ctx.setWebSocketAutoResponse(
      new WebSocketRequestResponsePair("ping", "pong"),
    );
  }

  async fetch(request) {
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);

    this.ctx.acceptWebSocket(server);

    const player = {
      id: crypto.randomUUID().slice(0, 8),
      name: assignName(new Set(this.#players().map((p) => p.name))),
    };
    // The attachment survives hibernation, so identity outlives the eviction of
    // this object's memory.
    server.serializeAttachment(player);

    const counter = await this.#counter();
    server.send(JSON.stringify({
      type: "welcome",
      you: player,
      counter,
      players: this.#players(),
    }));
    this.#broadcast({ type: "roster", players: this.#players() }, server);

    return new Response(null, { status: 101, webSocket: client });
  }

  async webSocketMessage(ws, message) {
    if (typeof message !== "string" || message.length > MAX_MESSAGE_BYTES) return;

    let msg;
    try {
      msg = JSON.parse(message);
    } catch {
      return;
    }

    if (msg?.type !== "click" || !this.#allow(ws)) return;

    const player = ws.deserializeAttachment();
    const value = (await this.#counter()) + 1;
    await this.ctx.storage.put("counter", value);
    this.#broadcast({ type: "counter", value, by: player?.name ?? "someone" });
  }

  webSocketClose(ws) {
    this.#broadcast({ type: "roster", players: this.#players(ws) }, ws);
  }

  webSocketError(ws) {
    this.#broadcast({ type: "roster", players: this.#players(ws) }, ws);
  }

  async #counter() {
    return (await this.ctx.storage.get("counter")) ?? 0;
  }

  /** Current roster, optionally excluding a socket that is on its way out. */
  #players(exclude = null) {
    return this.ctx.getWebSockets()
      .filter((ws) => ws !== exclude)
      .map((ws) => ws.deserializeAttachment())
      .filter(Boolean);
  }

  #broadcast(payload, exclude = null) {
    const body = JSON.stringify(payload);
    for (const ws of this.ctx.getWebSockets()) {
      if (ws === exclude) continue;
      try {
        ws.send(body);
      } catch {
        // Socket died between getWebSockets() and send(); the close handler
        // will take care of the roster.
      }
    }
  }

  /** Token bucket per socket. Memory-only: a hibernation wipe just refills it. */
  #allow(ws) {
    const now = Date.now();
    const bucket = this.#buckets.get(ws) ?? { tokens: MAX_CLICKS_PER_SECOND, at: now };
    const refill = ((now - bucket.at) / 1000) * MAX_CLICKS_PER_SECOND;
    bucket.tokens = Math.min(MAX_CLICKS_PER_SECOND, bucket.tokens + refill);
    bucket.at = now;
    if (bucket.tokens < 1) {
      this.#buckets.set(ws, bucket);
      return false;
    }
    bucket.tokens -= 1;
    this.#buckets.set(ws, bucket);
    return true;
  }
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname === "/health") {
      return Response.json({ ok: true, room: ROOM_NAME });
    }

    if (url.pathname !== "/ws") {
      return new Response("Not found", { status: 404 });
    }

    if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
      return new Response("Expected a WebSocket upgrade", { status: 426 });
    }

    // Single global room: every connection lands on the same instance.
    const id = env.ROOM.idFromName(ROOM_NAME);
    return env.ROOM.get(id).fetch(request);
  },
};
