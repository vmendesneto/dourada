import { advanceBot, isGameState, type GameState } from "./game";
import { DurableObject } from "cloudflare:workers";

export interface Env {
  GAME_TABLES: DurableObjectNamespace<GameTable>;
}

interface TableMetadata {
  tableNumber: string;
  playerToken: string;
  botActive: boolean;
  updatedAt: number;
  expiresAt: number | null;
}

const corsHeaders = (request: Request): Record<string, string> => ({
  "Access-Control-Allow-Origin": request.headers.get("Origin") ?? "*",
  "Access-Control-Allow-Headers": "Content-Type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  Vary: "Origin",
});

const json = (request: Request, value: unknown, status = 200): Response =>
  Response.json(value, { status, headers: corsHeaders(request) });

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders(request) });
    }
    const url = new URL(request.url);
    if (url.pathname === "/api/session" && request.method === "POST") {
      const payload = (await request.json().catch(() => ({}))) as Record<string, unknown>;
      const requestedTable = typeof payload.tableNumber === "string" ? payload.tableNumber : null;
      const requestedToken = typeof payload.playerToken === "string" ? payload.playerToken : null;
      if (requestedTable && requestedToken && /^\d{6}$/.test(requestedTable)) {
        const resumed = await tableStub(env, requestedTable).fetch(
          new Request("https://table.internal/session", {
            method: "POST",
            body: JSON.stringify({ playerToken: requestedToken }),
          }),
        );
        if (resumed.ok) {
          const result = (await resumed.json()) as Record<string, unknown>;
          return json(request, withConnectionUrl(url, requestedTable, result));
        }
      }

      if (!isGameState(payload.gameState)) {
        return json(request, { error: "Estado inicial da partida inválido." }, 400);
      }
      for (let attempt = 0; attempt < 12; attempt += 1) {
        const tableNumber = randomTableNumber();
        const playerToken = crypto.randomUUID();
        const created = await tableStub(env, tableNumber).fetch(
          new Request("https://table.internal/create", {
            method: "POST",
            body: JSON.stringify({ tableNumber, playerToken, gameState: payload.gameState }),
          }),
        );
        if (created.status === 409) continue;
        if (!created.ok) return json(request, { error: "Não foi possível criar a mesa." }, 503);
        const result = (await created.json()) as Record<string, unknown>;
        return json(request, withConnectionUrl(url, tableNumber, result), 201);
      }
      return json(request, { error: "Não foi possível reservar um número de mesa." }, 503);
    }

    const connection = url.pathname.match(/^\/api\/tables\/(\d{6})\/connect$/);
    if (connection) {
      return tableStub(env, connection[1]).fetch(request);
    }

    if (url.pathname === "/health") {
      return json(request, { ok: true, service: "dourada-mesas" });
    }
    return json(request, { error: "Rota não encontrada." }, 404);
  },
} satisfies ExportedHandler<Env>;

export class GameTable extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname === "/create" && request.method === "POST") return this.create(request);
    if (url.pathname === "/session" && request.method === "POST") return this.resume(request);
    if (url.pathname.match(/^\/api\/tables\/\d{6}\/connect$/)) {
      return this.connectSocket(request);
    }
    return new Response("Not found", { status: 404 });
  }

  async webSocketMessage(socket: WebSocket, message: string | ArrayBuffer): Promise<void> {
    if (typeof message !== "string") return;
    const attachment = socket.deserializeAttachment() as { playerToken?: string } | null;
    const metadata = await this.ctx.storage.get<TableMetadata>("metadata");
    if (!metadata || attachment?.playerToken !== metadata.playerToken) {
      socket.close(4003, "Sessão inválida");
      return;
    }
    const payload = JSON.parse(message) as Record<string, unknown>;
    if (payload.type === "state" && isGameState(payload.gameState)) {
      metadata.updatedAt = Date.now();
      metadata.botActive = false;
      await this.ctx.storage.put({ gameState: payload.gameState, metadata });
      socket.send(JSON.stringify({ type: "saved", updatedAt: metadata.updatedAt }));
    }
  }

  async webSocketClose(
    socket: WebSocket,
    code: number,
    reason: string,
    wasClean: boolean,
  ): Promise<void> {
    socket.close(code, reason);
    await this.startReplacementBot();
  }

  async webSocketError(socket: WebSocket): Promise<void> {
    socket.close(1011, "Erro de conexão");
    await this.startReplacementBot();
  }

  async alarm(): Promise<void> {
    const metadata = await this.ctx.storage.get<TableMetadata>("metadata");
    if (!metadata) return;
    if (metadata.expiresAt !== null && Date.now() >= metadata.expiresAt) {
      await this.ctx.storage.deleteAll();
      return;
    }
    if (this.ctx.getWebSockets().length > 0) {
      metadata.botActive = false;
      await this.ctx.storage.put("metadata", metadata);
      return;
    }
    const gameState = await this.ctx.storage.get<GameState>("gameState");
    if (!gameState) return;
    const step = advanceBot(gameState);
    metadata.botActive = true;
    metadata.updatedAt = Date.now();
    if (step.state.phase === "gameOver") {
      metadata.expiresAt = Date.now() + 60 * 60 * 1000;
    }
    await this.ctx.storage.put({ gameState: step.state, metadata });
    if (step.nextDelayMs !== null) {
      await this.ctx.storage.setAlarm(Date.now() + step.nextDelayMs);
    } else if (metadata.expiresAt !== null) {
      await this.ctx.storage.setAlarm(metadata.expiresAt);
    }
  }

  private async create(request: Request): Promise<Response> {
    const existing = await this.ctx.storage.get<TableMetadata>("metadata");
    if (existing) return new Response("Mesa ocupada", { status: 409 });
    const payload = (await request.json()) as {
      tableNumber: string;
      playerToken: string;
      gameState: unknown;
    };
    if (!isGameState(payload.gameState)) return new Response("Estado inválido", { status: 400 });
    const metadata: TableMetadata = {
      tableNumber: payload.tableNumber,
      playerToken: payload.playerToken,
      botActive: false,
      updatedAt: Date.now(),
      expiresAt: null,
    };
    await this.ctx.storage.put({ metadata, gameState: payload.gameState });
    return Response.json({
      tableNumber: metadata.tableNumber,
      playerToken: metadata.playerToken,
      botActive: false,
      gameState: payload.gameState,
    });
  }

  private async resume(request: Request): Promise<Response> {
    const metadata = await this.ctx.storage.get<TableMetadata>("metadata");
    const gameState = await this.ctx.storage.get<GameState>("gameState");
    if (!metadata || !gameState) return new Response("Mesa inexistente", { status: 404 });
    const payload = (await request.json()) as { playerToken?: string };
    if (payload.playerToken !== metadata.playerToken) {
      return new Response("Token inválido", { status: 403 });
    }
    if (gameState.phase === "gameOver") {
      await this.ctx.storage.deleteAll();
      return new Response("Partida encerrada", { status: 410 });
    }
    metadata.botActive = false;
    metadata.updatedAt = Date.now();
    metadata.expiresAt = null;
    await this.ctx.storage.put("metadata", metadata);
    await this.ctx.storage.deleteAlarm();
    return Response.json({
      tableNumber: metadata.tableNumber,
      playerToken: metadata.playerToken,
      botActive: false,
      gameState,
    });
  }

  private async connectSocket(request: Request): Promise<Response> {
    if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
      return new Response("WebSocket obrigatório", { status: 426 });
    }
    const metadata = await this.ctx.storage.get<TableMetadata>("metadata");
    const gameState = await this.ctx.storage.get<GameState>("gameState");
    const token = new URL(request.url).searchParams.get("token");
    if (!metadata || !gameState) return new Response("Mesa inexistente", { status: 404 });
    if (token !== metadata.playerToken) return new Response("Token inválido", { status: 403 });
    if (gameState.phase === "gameOver") return new Response("Partida encerrada", { status: 410 });

    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);
    this.ctx.acceptWebSocket(server);
    server.serializeAttachment({ playerToken: token });
    metadata.botActive = false;
    metadata.updatedAt = Date.now();
    await this.ctx.storage.put("metadata", metadata);
    await this.ctx.storage.deleteAlarm();
    server.send(JSON.stringify({ type: "state", gameState, tableNumber: metadata.tableNumber }));
    return new Response(null, { status: 101, webSocket: client });
  }

  private async startReplacementBot(): Promise<void> {
    const metadata = await this.ctx.storage.get<TableMetadata>("metadata");
    const gameState = await this.ctx.storage.get<GameState>("gameState");
    if (!metadata || !gameState) return;
    metadata.botActive = true;
    metadata.updatedAt = Date.now();
    if (gameState.phase === "gameOver") {
      metadata.expiresAt = Date.now() + 60 * 60 * 1000;
      await this.ctx.storage.put("metadata", metadata);
      await this.ctx.storage.setAlarm(metadata.expiresAt);
      return;
    }
    await this.ctx.storage.put("metadata", metadata);
    await this.ctx.storage.setAlarm(Date.now() + 1000);
  }
}

function tableStub(env: Env, tableNumber: string): DurableObjectStub<GameTable> {
  return env.GAME_TABLES.get(env.GAME_TABLES.idFromName(tableNumber));
}

function randomTableNumber(): string {
  const value = new Uint32Array(1);
  crypto.getRandomValues(value);
  return String(100000 + (value[0] % 900000));
}

function withConnectionUrl(
  requestUrl: URL,
  tableNumber: string,
  result: Record<string, unknown>,
): Record<string, unknown> {
  const protocol = requestUrl.protocol === "https:" ? "wss:" : "ws:";
  const token = encodeURIComponent(String(result.playerToken));
  return {
    ...result,
    websocketUrl: `${protocol}//${requestUrl.host}/api/tables/${tableNumber}/connect?token=${token}`,
  };
}
