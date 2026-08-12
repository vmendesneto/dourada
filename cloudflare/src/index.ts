import {
  advanceBot,
  createInitialGame,
  isGameState,
  pendingTenTeam,
  type GameState,
} from "./game";
import { DurableObject } from "cloudflare:workers";

export interface Env {
  GAME_TABLES: DurableObjectNamespace<GameTable>;
}

type TablePhase = "empty" | "waiting" | "playing";
type SeatKind = "human" | "bot";

interface TableSeat {
  kind: SeatKind;
  name: string;
  token: string | null;
  joinedAt: number;
  disconnectedAt: number | null;
}

interface SharedTableState {
  version: 2;
  tableNumber: number;
  phase: TablePhase;
  seats: Array<TableSeat | null>;
  gameState: GameState | null;
  nextActionAt: number | null;
  updatedAt: number;
}

interface SocketAttachment {
  token: string;
  seatIndex: number;
  connectedAt: number;
}

const tableCount = 10;
const seatCount = 6;
const disconnectGraceMs = 5000;
const connectionCheckMs = 5000;
const humanTurnMs = 15000;

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
    if (url.pathname === "/api/lobby" && request.method === "GET") {
      const tables = await Promise.all(
        Array.from({ length: tableCount }, async (_, index) => {
          const tableNumber = index + 1;
          const response = await tableStub(env, tableNumber).fetch(
            `https://table.internal/status?tableNumber=${tableNumber}`,
          );
          return response.json();
        }),
      );
      return json(request, { tables });
    }

    const action = url.pathname.match(
      /^\/api\/tables\/(10|[1-9])\/(join|fill-bots|connect)$/,
    );
    if (action) {
      const tableNumber = Number(action[1]);
      const operation = action[2];
      if (operation === "connect") {
        return tableStub(env, tableNumber).fetch(request);
      }
      if (request.method !== "POST") {
        return json(request, { error: "Método não permitido." }, 405);
      }
      const internal = await tableStub(env, tableNumber).fetch(
        new Request(`https://table.internal/${operation}?tableNumber=${tableNumber}`, {
          method: "POST",
          body: await request.text(),
        }),
      );
      const body = (await internal.json().catch(() => ({
        error: "Não foi possível acessar a mesa.",
      }))) as Record<string, unknown>;
      if (!internal.ok) return json(request, body, internal.status);
      return json(
        request,
        {
          ...body,
          websocketUrl: connectionUrl(url, tableNumber, String(body.playerToken)),
        },
        internal.status,
      );
    }

    if (url.pathname === "/health") {
      return json(request, {
        ok: true,
        service: "dourada-mesas",
        tableLimit: tableCount,
      });
    }
    return json(request, { error: "Rota não encontrada." }, 404);
  },
} satisfies ExportedHandler<Env>;

export class GameTable extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair("ping", "pong"));
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    const requestedTableNumber = Number(url.searchParams.get("tableNumber")) || undefined;
    if (url.pathname === "/status") {
      return Response.json(this.status(await this.load(requestedTableNumber)));
    }
    if (url.pathname === "/join" && request.method === "POST") {
      return this.join(request, requestedTableNumber);
    }
    if (url.pathname === "/fill-bots" && request.method === "POST") {
      return this.fillBots(request, requestedTableNumber);
    }
    if (url.pathname.match(/^\/api\/tables\/(10|[1-9])\/connect$/)) {
      return this.connectSocket(request);
    }
    return Response.json({ error: "Rota interna inexistente." }, { status: 404 });
  }

  async webSocketMessage(socket: WebSocket, message: string | ArrayBuffer): Promise<void> {
    if (typeof message !== "string") return;
    const attachment = socket.deserializeAttachment() as SocketAttachment | null;
    const table = await this.load();
    if (!attachment || !this.validHuman(table, attachment.seatIndex, attachment.token)) {
      socket.close(4003, "Sessão inválida");
      return;
    }

    let payload: Record<string, unknown>;
    try {
      payload = JSON.parse(message) as Record<string, unknown>;
    } catch {
      return;
    }

    if (payload.type === "state" && table.phase === "playing") {
      if (!isGameState(payload.gameState) || !this.canSeatSubmit(table, attachment.seatIndex)) {
        socket.send(JSON.stringify({ type: "rejected", reason: "Jogada inválida." }));
        return;
      }
      table.gameState = payload.gameState;
      table.updatedAt = Date.now();
      table.nextActionAt = this.nextActionAt(table, this.activeHumanSeats());
      await this.saveAndSchedule(table);
      this.broadcast(table);
      return;
    }

    if (payload.type === "restart" && table.gameState?.phase === "gameOver") {
      table.phase = "waiting";
      table.gameState = null;
      table.nextActionAt = null;
      table.seats = table.seats.map((seat) => (seat?.kind === "human" ? seat : null));
      table.updatedAt = Date.now();
      await this.saveAndSchedule(table);
      this.broadcast(table);
    }
  }

  async webSocketClose(
    socket: WebSocket,
    code: number,
    reason: string,
    wasClean: boolean,
  ): Promise<void> {
    await this.markDisconnected(socket);
    socket.close(code, reason);
  }

  async webSocketError(socket: WebSocket): Promise<void> {
    await this.markDisconnected(socket);
    socket.close(1011, "Erro de conexão");
  }

  async alarm(): Promise<void> {
    const table = await this.load();
    if (table.phase === "empty") return;

    const now = Date.now();
    const activeHumans = this.activeHumanSeats();
    this.refreshDisconnections(table, activeHumans, now);

    if (table.phase === "waiting") {
      for (let index = 0; index < table.seats.length; index += 1) {
        const seat = table.seats[index];
        if (
          seat?.kind === "human" &&
          !activeHumans.has(index) &&
          seat.disconnectedAt !== null &&
          now - seat.disconnectedAt >= disconnectGraceMs
        ) {
          table.seats[index] = null;
        }
      }
      if (!table.seats.some((seat) => seat?.kind === "human")) {
        await this.ctx.storage.deleteAll();
        return;
      }
      table.updatedAt = now;
      await this.saveAndSchedule(table);
      this.broadcast(table);
      return;
    }

    const game = table.gameState;
    if (!game) {
      await this.ctx.storage.deleteAll();
      return;
    }

    if (game.phase === "gameOver") {
      if (activeHumans.size === 0 && this.allHumansPastGrace(table, now)) {
        await this.ctx.storage.deleteAll();
        return;
      }
      await this.saveAndSchedule(table);
      return;
    }

    const expectedSeat = this.expectedHumanSeat(table);
    if (expectedSeat !== null && !activeHumans.has(expectedSeat)) {
      const disconnectedAt = table.seats[expectedSeat]?.disconnectedAt ?? now;
      table.nextActionAt = Math.min(
        table.nextActionAt ?? disconnectedAt + disconnectGraceMs,
        disconnectedAt + disconnectGraceMs,
      );
    }

    if (table.nextActionAt !== null && now >= table.nextActionAt) {
      const step = advanceBot(game);
      table.gameState = step.state;
      table.updatedAt = now;
      if (step.state.phase === "gameOver" && activeHumans.size === 0) {
        await this.ctx.storage.deleteAll();
        return;
      }
      table.nextActionAt = this.nextActionAt(table, activeHumans, step.nextDelayMs);
      this.broadcast(table);
    }
    await this.saveAndSchedule(table);
  }

  private async join(request: Request, tableNumber?: number): Promise<Response> {
    const payload = (await request.json().catch(() => ({}))) as {
      playerToken?: string;
      playerName?: string;
    };
    const table = await this.load(tableNumber);

    if (payload.playerToken) {
      const existingSeat = table.seats.findIndex(
        (seat) => seat?.kind === "human" && seat.token === payload.playerToken,
      );
      if (existingSeat >= 0) {
        table.seats[existingSeat]!.disconnectedAt = null;
        table.updatedAt = Date.now();
        await this.saveAndSchedule(table);
        return Response.json(this.entry(table, existingSeat), { status: 200 });
      }
    }

    if (table.phase === "playing") {
      return Response.json({ error: "A partida desta mesa já começou." }, { status: 409 });
    }
    const seatIndex = table.seats.findIndex((seat) => seat === null);
    if (seatIndex < 0) {
      return Response.json({ error: "Esta mesa não tem cadeira disponível." }, { status: 409 });
    }

    const now = Date.now();
    const token = crypto.randomUUID();
    table.phase = "waiting";
    table.seats[seatIndex] = {
      kind: "human",
      name: cleanPlayerName(payload.playerName, seatIndex),
      token,
      joinedAt: now,
      disconnectedAt: now,
    };
    table.updatedAt = now;

    if (table.seats.every((seat) => seat !== null)) this.startGame(table);
    await this.saveAndSchedule(table);
    this.broadcast(table);
    return Response.json(this.entry(table, seatIndex), { status: 201 });
  }

  private async fillBots(request: Request, tableNumber?: number): Promise<Response> {
    const payload = (await request.json().catch(() => ({}))) as { playerToken?: string };
    const table = await this.load(tableNumber);
    const seatIndex = table.seats.findIndex(
      (seat) => seat?.kind === "human" && seat.token === payload.playerToken,
    );
    if (seatIndex < 0) {
      return Response.json({ error: "Jogador não pertence à mesa." }, { status: 403 });
    }
    if (table.phase !== "waiting") {
      return Response.json({ error: "A mesa não está aguardando jogadores." }, { status: 409 });
    }

    const now = Date.now();
    for (let index = 0; index < table.seats.length; index += 1) {
      if (table.seats[index] === null) {
        table.seats[index] = {
          kind: "bot",
          name: `Robô ${index + 1}`,
          token: null,
          joinedAt: now,
          disconnectedAt: null,
        };
      }
    }
    this.startGame(table);
    await this.saveAndSchedule(table);
    this.broadcast(table);
    return Response.json(this.entry(table, seatIndex));
  }

  private async connectSocket(request: Request): Promise<Response> {
    if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
      return new Response("WebSocket obrigatório", { status: 426 });
    }
    const table = await this.load();
    const token = new URL(request.url).searchParams.get("token");
    const seatIndex = table.seats.findIndex(
      (seat) => seat?.kind === "human" && seat.token === token,
    );
    if (seatIndex < 0 || token === null) {
      return new Response("Sessão inválida", { status: 403 });
    }

    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);
    this.ctx.acceptWebSocket(server, [`seat:${seatIndex}`]);
    server.serializeAttachment({ token, seatIndex, connectedAt: Date.now() });
    for (const oldSocket of this.ctx.getWebSockets(`seat:${seatIndex}`)) {
      if (oldSocket !== server) oldSocket.close(4000, "Conexão substituída");
    }
    table.seats[seatIndex]!.disconnectedAt = null;
    table.updatedAt = Date.now();
    if (table.phase === "playing") {
      table.nextActionAt = this.nextActionAt(table, this.activeHumanSeats());
    }
    await this.saveAndSchedule(table);
    server.send(JSON.stringify(this.roomMessage(table, seatIndex)));
    this.broadcast(table, server);
    return new Response(null, { status: 101, webSocket: client });
  }

  private async markDisconnected(socket: WebSocket): Promise<void> {
    const attachment = socket.deserializeAttachment() as SocketAttachment | null;
    if (!attachment) return;
    const table = await this.load();
    if (!this.validHuman(table, attachment.seatIndex, attachment.token)) return;
    table.seats[attachment.seatIndex]!.disconnectedAt = Date.now();
    table.updatedAt = Date.now();
    await this.saveAndSchedule(table);
    this.broadcast(table, socket);
  }

  private startGame(table: SharedTableState): void {
    table.phase = "playing";
    table.gameState = createInitialGame();
    table.updatedAt = Date.now();
    table.nextActionAt = this.nextActionAt(table, this.activeHumanSeats());
  }

  private entry(table: SharedTableState, seatIndex: number): Record<string, unknown> {
    return {
      tableNumber: String(table.tableNumber),
      playerToken: table.seats[seatIndex]!.token,
      seatIndex,
      phase: table.phase,
      seats: publicSeats(table),
      gameState: table.gameState,
      status: this.status(table),
    };
  }

  private status(table: SharedTableState): Record<string, unknown> {
    const humanCount = table.seats.filter((seat) => seat?.kind === "human").length;
    const botCount = table.seats.filter((seat) => seat?.kind === "bot").length;
    return {
      tableNumber: table.tableNumber,
      status: table.phase,
      playerCount: humanCount + botCount,
      humanCount,
      botCount,
      capacity: seatCount,
      seats: publicSeats(table),
    };
  }

  private roomMessage(table: SharedTableState, seatIndex: number): Record<string, unknown> {
    return {
      type: "room",
      phase: table.phase,
      tableNumber: String(table.tableNumber),
      seatIndex,
      seats: publicSeats(table),
      gameState: table.gameState,
    };
  }

  private broadcast(table: SharedTableState, except?: WebSocket): void {
    for (const socket of this.ctx.getWebSockets()) {
      if (socket === except || socket.readyState !== WebSocket.OPEN) continue;
      const attachment = socket.deserializeAttachment() as SocketAttachment | null;
      if (!attachment) continue;
      socket.send(JSON.stringify(this.roomMessage(table, attachment.seatIndex)));
    }
  }

  private activeHumanSeats(): Set<number> {
    const now = Date.now();
    const active = new Set<number>();
    for (const socket of this.ctx.getWebSockets()) {
      if (socket.readyState !== WebSocket.OPEN) continue;
      const attachment = socket.deserializeAttachment() as SocketAttachment | null;
      if (!attachment) continue;
      const heartbeat =
        this.ctx.getWebSocketAutoResponseTimestamp(socket)?.getTime() ??
        attachment.connectedAt;
      if (now - heartbeat <= disconnectGraceMs) active.add(attachment.seatIndex);
    }
    return active;
  }

  private refreshDisconnections(
    table: SharedTableState,
    activeHumans: Set<number>,
    now: number,
  ): void {
    for (let index = 0; index < table.seats.length; index += 1) {
      const seat = table.seats[index];
      if (seat?.kind !== "human") continue;
      if (activeHumans.has(index)) seat.disconnectedAt = null;
      else seat.disconnectedAt ??= now;
    }
  }

  private expectedHumanSeat(table: SharedTableState): number | null {
    const game = table.gameState;
    if (!game || game.phase !== "playing") return null;
    if (game.pendingChallenge !== null) {
      return this.firstHumanOnTeam(table, game.pendingChallenge.targetTeam);
    }
    const tenTeam = pendingTenTeam(game);
    if (tenTeam !== null) return this.firstHumanOnTeam(table, tenTeam);
    const seat = table.seats[game.currentPlayerIndex];
    return seat?.kind === "human" ? game.currentPlayerIndex : null;
  }

  private firstHumanOnTeam(table: SharedTableState, team: number): number | null {
    const index = table.seats.findIndex(
      (seat, seatIndex) => seat?.kind === "human" && seatIndex % 2 === team,
    );
    return index < 0 ? null : index;
  }

  private canSeatSubmit(table: SharedTableState, seatIndex: number): boolean {
    const game = table.gameState;
    if (!game) return false;
    if (game.challengeNotice !== null) return true;
    if (game.pendingChallenge !== null) {
      return seatIndex % 2 === game.pendingChallenge.targetTeam;
    }
    const tenTeam = pendingTenTeam(game);
    if (tenTeam !== null) return seatIndex % 2 === tenTeam;
    return game.currentPlayerIndex === seatIndex;
  }

  private nextActionAt(
    table: SharedTableState,
    activeHumans: Set<number>,
    engineDelayMs?: number | null,
  ): number | null {
    const game = table.gameState;
    if (!game || game.phase === "gameOver") return null;
    const now = Date.now();
    if (engineDelayMs !== undefined && engineDelayMs !== null) {
      const expectedHuman = this.expectedHumanSeat(table);
      if (expectedHuman === null || !activeHumans.has(expectedHuman)) {
        return now + engineDelayMs;
      }
    }
    if (
      game.phase === "handFinished" ||
      game.awaitingNextTrick ||
      game.challengeNotice !== null
    ) {
      return now + 5000;
    }
    const expectedHuman = this.expectedHumanSeat(table);
    if (expectedHuman !== null && activeHumans.has(expectedHuman)) {
      return now + humanTurnMs;
    }
    if (expectedHuman !== null) {
      const disconnectedAt = table.seats[expectedHuman]?.disconnectedAt ?? now;
      return disconnectedAt + disconnectGraceMs;
    }
    return now + 650;
  }

  private allHumansPastGrace(table: SharedTableState, now: number): boolean {
    return table.seats.every(
      (seat) =>
        seat?.kind !== "human" ||
        (seat.disconnectedAt !== null && now - seat.disconnectedAt >= disconnectGraceMs),
    );
  }

  private validHuman(table: SharedTableState, seatIndex: number, token: string): boolean {
    const seat = table.seats[seatIndex];
    return seat?.kind === "human" && seat.token === token;
  }

  private async load(requestedTableNumber?: number): Promise<SharedTableState> {
    const stored = await this.ctx.storage.get<SharedTableState>("table");
    if (stored?.version === 2) return stored;
    const tableNumber = requestedTableNumber ?? 1;
    return {
      version: 2,
      tableNumber,
      phase: "empty",
      seats: Array.from({ length: seatCount }, () => null),
      gameState: null,
      nextActionAt: null,
      updatedAt: Date.now(),
    };
  }

  private async saveAndSchedule(table: SharedTableState): Promise<void> {
    await this.ctx.storage.put("table", table);
    const now = Date.now();
    let alarmAt = now + connectionCheckMs;
    if (table.nextActionAt !== null) alarmAt = Math.min(alarmAt, table.nextActionAt);
    await this.ctx.storage.setAlarm(alarmAt);
  }
}

function tableStub(env: Env, tableNumber: number): DurableObjectStub<GameTable> {
  return env.GAME_TABLES.getByName(`fixed-table-${tableNumber}`);
}

function publicSeats(table: SharedTableState): Array<Record<string, unknown> | null> {
  return table.seats.map((seat, index) =>
    seat === null
      ? null
      : {
          index,
          kind: seat.kind,
          name: seat.name,
          team: index % 2,
          connected: seat.kind === "bot" || seat.disconnectedAt === null,
        },
  );
}

function connectionUrl(requestUrl: URL, tableNumber: number, token: string): string {
  const protocol = requestUrl.protocol === "https:" ? "wss:" : "ws:";
  return `${protocol}//${requestUrl.host}/api/tables/${tableNumber}/connect?token=${encodeURIComponent(token)}`;
}

function cleanPlayerName(value: string | undefined, seatIndex: number): string {
  const clean = value?.trim().replace(/\s+/g, " ").slice(0, 20);
  return clean ? clean : `Jogador ${seatIndex + 1}`;
}
