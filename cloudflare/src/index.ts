import {
  acceptPendingChallenge,
  advanceBot,
  betweenPartidasTransitionMs,
  challengeAnimationMs,
  challengeNoticeMs,
  createInitialGame,
  foldPendingChallenge,
  handTransitionMs,
  isGameState,
  pendingTenTeam,
  raisePendingChallenge,
  type GameState,
} from "./game";
import { DurableObject } from "cloudflare:workers";
import {
  isLobbyTableStatus,
  type LobbyTablePhase,
  type LobbyTableStatus,
} from "./lobby";
import { verifyFirebaseIdToken } from "./firebase_auth";
import {
  createFillBotsVote,
  fillBotsVoteDecision,
  recordFillBotsVote,
  recordFillBotsVoteShown,
  type FillBotsVote,
} from "./fill_bots_vote";
import {
  challengeVoteDecision,
  createChallengeVote,
  recordChallengeVote,
  removeChallengeVoteParticipant,
  type ChallengeVote,
  type ChallengeVoteChoice,
} from "./challenge_vote";

type TablePhase = LobbyTablePhase;
type SeatKind = "human" | "bot";

interface TableSeat {
  kind: SeatKind;
  name: string;
  photoUrl?: string | null;
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
  waitingStartAt: number | null;
  fillBotsVote: FillBotsVote | null;
  challengeVote: ChallengeVote | null;
  updatedAt: number;
}

interface SocketAttachment {
  role?: "player" | "spectator";
  token: string;
  seatIndex: number;
  connectedAt: number;
}

interface LobbyState {
  version: 1;
  tables: LobbyTableStatus[];
}

const tableCount = 10;
const seatCount = 6;
const disconnectGraceMs = 5000;
const humanTurnMs = 15000;
const botAvatarCount = 10;
const fillBotsVotingVersion = 2;
const challengeVotingVersion = 1;

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
    if (url.pathname === "/api/lobby/connect" && request.method === "GET") {
      return lobbyStub(env).fetch(request);
    }
    if (url.pathname === "/api/lobby" && request.method === "GET") {
      const response = await lobbyStub(env).fetch("https://lobby.internal/snapshot");
      return json(request, await response.json(), response.status);
    }

    const action = url.pathname.match(
      /^\/api\/tables\/(10|[1-9])\/(join|watch|fill-bots|can-resume|decline-resume|leave|connect|watch-connect)$/,
    );
    if (action) {
      const tableNumber = Number(action[1]);
      const operation = action[2];
      if (operation === "connect" || operation === "watch-connect") {
        return tableStub(env, tableNumber).fetch(request);
      }
      if (request.method !== "POST") {
        return json(request, { error: "Método não permitido." }, 405);
      }
      const requestBody = await readSmallBody(request);
      if (requestBody === null) {
        return json(request, { error: "Requisição muito grande." }, 413);
      }
      let internalBody = requestBody;
      if (operation === "join") {
        const payload = parseRecord(requestBody);
        if (payload === null) {
          return json(request, { error: "Dados de entrada inválidos." }, 400);
        }
        const playerToken =
          typeof payload.playerToken === "string" ? payload.playerToken : undefined;
        const playerName =
          typeof payload.playerName === "string" ? payload.playerName : undefined;
        const identity = await verifyFirebaseIdToken(payload.firebaseIdToken);
        if (!identity && !playerToken) {
          return json(request, { error: "Faça login para entrar em uma mesa." }, 401);
        }
        internalBody = JSON.stringify({
          playerToken,
          playerName: identity?.displayName ?? playerName,
          photoUrl: identity?.photoUrl ?? null,
          firebaseAuthenticated: identity !== null,
        });
      }
      const internal = await tableStub(env, tableNumber).fetch(
        new Request(`https://table.internal/${operation}?tableNumber=${tableNumber}`, {
          method: "POST",
          body: internalBody,
        }),
      );
      const body = (await internal.json().catch(() => ({
        error: "Não foi possível acessar a mesa.",
      }))) as Record<string, unknown>;
      if (!internal.ok) return json(request, body, internal.status);
      if (
        operation === "can-resume" ||
        operation === "decline-resume" ||
        operation === "leave"
      ) {
        return json(request, body, internal.status);
      }
      return json(
        request,
        {
          ...body,
          websocketUrl: connectionUrl(
            url,
            tableNumber,
            String(body.playerToken),
            operation === "watch" ? "watch-connect" : "connect",
          ),
        },
        internal.status,
      );
    }

    if (url.pathname === "/health") {
      return json(request, {
        ok: true,
        service: "dourada-mesas",
        tableLimit: tableCount,
        fillBotsVotingVersion,
        challengeVotingVersion,
      });
    }
    return json(request, { error: "Rota não encontrada." }, 404);
  },
} satisfies ExportedHandler<Env>;

export class GameLobby extends DurableObject<Env> {
  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname === "/api/lobby/connect") {
      if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
        return new Response("WebSocket obrigatório", { status: 426 });
      }
      const state = await this.load();
      const pair = new WebSocketPair();
      const [client, server] = Object.values(pair);
      this.ctx.acceptWebSocket(server);
      server.send(JSON.stringify({ type: "lobby", tables: state.tables }));
      return new Response(null, { status: 101, webSocket: client });
    }
    if (url.pathname === "/snapshot") {
      return Response.json(await this.load());
    }
    if (url.pathname === "/update" && request.method === "POST") {
      const value = await request.json().catch(() => null);
      if (!isLobbyTableStatus(value)) {
        return Response.json({ error: "Estado de mesa inválido." }, { status: 400 });
      }
      const state = await this.load();
      const current = state.tables[value.tableNumber - 1];
      if (JSON.stringify(current) === JSON.stringify(value)) {
        return Response.json({ updated: false });
      }
      state.tables[value.tableNumber - 1] = value;
      await this.ctx.storage.put("lobby", state);
      this.broadcast(state.tables);
      return Response.json({ updated: true });
    }
    return Response.json({ error: "Rota interna inexistente." }, { status: 404 });
  }

  webSocketClose(socket: WebSocket, code: number, reason: string): void {
    socket.close(code, reason);
  }

  webSocketError(socket: WebSocket): void {
    socket.close(1011, "Erro de conexão");
  }

  private async load(): Promise<LobbyState> {
    const stored = await this.ctx.storage.get<LobbyState>("lobby");
    if (stored?.version === 1 && stored.tables.length === tableCount) return stored;

    const tables = await Promise.all(
      Array.from({ length: tableCount }, async (_, index) => {
        const tableNumber = index + 1;
        const response = await tableStub(this.env, tableNumber).fetch(
          `https://table.internal/status?tableNumber=${tableNumber}`,
        );
        return (await response.json()) as LobbyTableStatus;
      }),
    );
    const state: LobbyState = { version: 1, tables };
    await this.ctx.storage.put("lobby", state);
    return state;
  }

  private broadcast(tables: LobbyTableStatus[]): void {
    const message = JSON.stringify({ type: "lobby", tables });
    for (const socket of this.ctx.getWebSockets()) {
      if (socket.readyState === WebSocket.OPEN) socket.send(message);
    }
  }
}

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
    if (url.pathname === "/watch" && request.method === "POST") {
      return this.watch(requestedTableNumber);
    }
    if (url.pathname === "/fill-bots" && request.method === "POST") {
      return this.fillBots(request, requestedTableNumber);
    }
    if (url.pathname === "/can-resume" && request.method === "POST") {
      return this.canResume(request, requestedTableNumber);
    }
    if (url.pathname === "/decline-resume" && request.method === "POST") {
      return this.declineResume(request, requestedTableNumber);
    }
    if (url.pathname === "/leave" && request.method === "POST") {
      return this.declineResume(request, requestedTableNumber);
    }
    if (url.pathname.match(/^\/api\/tables\/(10|[1-9])\/connect$/)) {
      return this.connectSocket(request);
    }
    if (url.pathname.match(/^\/api\/tables\/(10|[1-9])\/watch-connect$/)) {
      return this.connectSpectatorSocket(request);
    }
    return Response.json({ error: "Rota interna inexistente." }, { status: 404 });
  }

  async webSocketMessage(socket: WebSocket, message: string | ArrayBuffer): Promise<void> {
    if (typeof message !== "string") return;
    const attachment = socket.deserializeAttachment() as SocketAttachment | null;
    const table = await this.load();
    if (!attachment) {
      socket.close(4003, "Sessão inválida");
      return;
    }
    if (attachment.role === "spectator") return;
    if (!this.validHuman(table, attachment.seatIndex, attachment.token)) {
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
      this.ensureChallengeVote(table);
      table.updatedAt = Date.now();
      table.nextActionAt = this.nextActionAt(table, this.activeHumanSeats());
      await this.saveAndSchedule(table);
      this.broadcast(table);
      return;
    }

    if (payload.type === "challengeVote" && table.phase === "playing") {
      const vote = table.challengeVote;
      const game = table.gameState;
      const choice = payload.choice;
      if (
        vote === null ||
        game === null ||
        game.pendingChallenge === null ||
        payload.voteId !== vote.id ||
        !isChallengeVoteChoice(choice) ||
        (choice === "raise" && game.pendingChallenge.requestedValue >= 6)
      ) {
        return;
      }
      const now = Date.now();
      if (now >= vote.expiresAt) {
        this.resolveChallengeVote(table, attachment.seatIndex, now);
        await this.saveAndSchedule(table);
        this.broadcast(table);
        return;
      }
      if (!recordChallengeVote(vote, attachment.seatIndex, choice)) return;
      this.resolveChallengeVote(table, attachment.seatIndex, now);
      await this.saveAndSchedule(table);
      this.broadcast(table);
      return;
    }

    if (payload.type === "restart" && table.gameState?.phase === "gameOver") {
      this.returnToWaitingRoom(table, Date.now());
      await this.saveAndSchedule(table, true);
      this.broadcast(table);
      this.closeSpectators();
      return;
    }

    if (payload.type === "fillBotsVoteShown" && table.phase === "waiting") {
      const vote = table.fillBotsVote;
      if (vote === null || payload.voteId !== vote.id) return;
      if (!recordFillBotsVoteShown(vote, attachment.seatIndex, Date.now())) return;
      await this.saveAndSchedule(table, true);
      this.broadcast(table);
      return;
    }

    if (payload.type === "fillBotsVote" && table.phase === "waiting") {
      const vote = table.fillBotsVote;
      if (
        vote === null ||
        payload.voteId !== vote.id ||
        typeof payload.accepted !== "boolean"
      ) return;
      if (!recordFillBotsVote(vote, attachment.seatIndex, payload.accepted)) return;
      this.resolveFillBotsVote(table, Date.now());
      await this.saveAndSchedule(table, true);
      this.broadcast(table);
    }
  }

  async webSocketClose(
    socket: WebSocket,
    code: number,
    reason: string,
    wasClean: boolean,
  ): Promise<void> {
    const attachment = socket.deserializeAttachment() as SocketAttachment | null;
    if (attachment?.role === "spectator") {
      const table = await this.load();
      this.broadcast(table);
      socket.close(code, reason);
      return;
    }
    await this.markDisconnected(socket);
    socket.close(code, reason);
  }

  async webSocketError(socket: WebSocket): Promise<void> {
    const attachment = socket.deserializeAttachment() as SocketAttachment | null;
    if (attachment?.role === "spectator") {
      const table = await this.load();
      this.broadcast(table);
      socket.close(1011, "Erro de conexão");
      return;
    }
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
          now - seat.disconnectedAt >= disconnectGraceMs &&
          !(
            table.fillBotsVote?.participantSeatIndexes.includes(index) &&
            (table.fillBotsVote.expiresAt === null ||
              now < table.fillBotsVote.expiresAt)
          )
        ) {
          table.seats[index] = null;
        }
      }
      if (!table.seats.some((seat) => seat?.kind === "human")) {
        await this.clearTable(table.tableNumber);
        return;
      }
      if (table.fillBotsVote !== null) {
        this.resolveFillBotsVote(table, now);
      }
      this.syncWaitingCountdown(table, now, activeHumans);
      table.updatedAt = now;
      await this.saveAndSchedule(table, true);
      this.broadcast(table);
      return;
    }

    const game = table.gameState;
    if (!game) {
      await this.clearTable(table.tableNumber);
      return;
    }

    if (game.phase === "gameOver") {
      if (activeHumans.size === 0 && this.allHumansPastGrace(table, now)) {
        await this.clearTable(table.tableNumber);
        return;
      }
      if (activeHumans.size > 0) {
        this.returnToWaitingRoom(table, now);
        await this.saveAndSchedule(table, true);
        this.broadcast(table);
        this.closeSpectators();
        return;
      }
      table.nextActionAt = null;
      await this.saveAndSchedule(table);
      return;
    }

    if (table.challengeVote !== null && now >= table.challengeVote.expiresAt) {
      this.resolveChallengeVote(table, -1, now);
      await this.saveAndSchedule(table);
      this.broadcast(table);
      return;
    }

    if (game.pendingChallenge === null) {
      const expectedSeat = this.expectedHumanSeat(table);
      if (expectedSeat !== null && !activeHumans.has(expectedSeat)) {
        const disconnectedAt = table.seats[expectedSeat]?.disconnectedAt ?? now;
        table.nextActionAt = Math.min(
          table.nextActionAt ?? disconnectedAt + disconnectGraceMs,
          disconnectedAt + disconnectGraceMs,
        );
      }
    }

    if (table.nextActionAt !== null && now >= table.nextActionAt) {
      const step = advanceBot(game);
      table.gameState = step.state;
      this.ensureChallengeVote(table);
      table.updatedAt = now;
      if (step.state.phase === "gameOver" && activeHumans.size === 0) {
        await this.clearTable(table.tableNumber);
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
      photoUrl?: string | null;
      firebaseAuthenticated?: boolean;
    };
    const table = await this.load(tableNumber);

    if (payload.playerToken) {
      const existingSeat = table.seats.findIndex(
        (seat) => seat?.kind === "human" && seat.token === payload.playerToken,
      );
      if (existingSeat >= 0) {
        const seat = table.seats[existingSeat]!;
        seat.disconnectedAt = Date.now();
        if (payload.firebaseAuthenticated === true) {
          seat.name = cleanPlayerName(payload.playerName, existingSeat);
          seat.photoUrl = cleanPhotoUrl(payload.photoUrl);
        }
        table.updatedAt = Date.now();
        await this.saveAndSchedule(table, true);
        return Response.json(this.entry(table, existingSeat), { status: 200 });
      }
    }

    if (payload.firebaseAuthenticated !== true) {
      return Response.json({ error: "Faça login para entrar em uma mesa." }, { status: 401 });
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
      photoUrl: cleanPhotoUrl(payload.photoUrl),
      token,
      joinedAt: now,
      disconnectedAt: now,
    };
    table.updatedAt = now;

    await this.saveAndSchedule(table, true);
    this.broadcast(table);
    return Response.json(this.entry(table, seatIndex), { status: 201 });
  }

  private async watch(tableNumber?: number): Promise<Response> {
    const table = await this.load(tableNumber);
    if (
      table.phase !== "playing" ||
      table.gameState === null ||
      table.gameState.phase === "gameOver"
    ) {
      return Response.json(
        { error: "Esta partida não está disponível para assistir." },
        { status: 409 },
      );
    }
    const token = crypto.randomUUID();
    return Response.json({
      tableNumber: String(table.tableNumber),
      playerToken: token,
      seatIndex: 0,
      spectator: true,
      spectatorCount: this.spectatorCount(),
      spectatorHandCounts: spectatorHandCounts(table.gameState),
      phase: table.phase,
      seats: publicSeats(table),
      gameState: spectatorGameState(table.gameState),
      fillBotsVotingVersion: 0,
      challengeVotingVersion: 0,
      fillBotsVote: null,
      challengeVote: null,
      waitingStartAt: null,
    });
  }

  private async fillBots(request: Request, tableNumber?: number): Promise<Response> {
    const payload = (await request.json().catch(() => ({}))) as {
      playerToken?: string;
      humanSeatIndexes?: unknown;
    };
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
    if (table.fillBotsVote !== null) {
      return Response.json({ error: "Já existe uma votação em andamento." }, { status: 409 });
    }

    const now = Date.now();
    const participantSeatIndexes = table.seats.flatMap((seat, index) =>
      seat?.kind === "human" ? [index] : [],
    );
    const clientHumanSeatIndexes = Array.isArray(payload.humanSeatIndexes)
      ? payload.humanSeatIndexes.filter(
          (index): index is number => Number.isInteger(index),
        )
      : [];
    if (
      clientHumanSeatIndexes.length !== participantSeatIndexes.length ||
      clientHumanSeatIndexes.some(
        (index, position) => index !== participantSeatIndexes[position],
      )
    ) {
      return Response.json(
        { error: "A lista de jogadores mudou. Aguarde a sala atualizar." },
        { status: 409 },
      );
    }
    const activeHumans = this.activeHumanSeats();
    if (participantSeatIndexes.some((index) => !activeHumans.has(index))) {
      return Response.json(
        { error: "Aguarde todos os jogadores humanos estarem conectados." },
        { status: 409 },
      );
    }
    table.fillBotsVote = createFillBotsVote(
      crypto.randomUUID(),
      seatIndex,
      participantSeatIndexes,
      now,
      seatCount,
    );
    this.resolveFillBotsVote(table, now);
    await this.saveAndSchedule(table, true);
    this.broadcast(table);
    return Response.json(this.entry(table, seatIndex));
  }

  private resolveFillBotsVote(table: SharedTableState, now: number): void {
    const vote = table.fillBotsVote;
    if (vote === null) return;
    const decision = fillBotsVoteDecision(vote, now);
    table.updatedAt = now;
    if (decision === "pending") return;

    table.fillBotsVote = null;
    if (decision === "rejected") return;
    for (let index = 0; index < table.seats.length; index += 1) {
      if (table.seats[index] === null) {
        table.seats[index] = {
          kind: "bot",
          name: `Robô ${index + 1}`,
          photoUrl: randomBotAvatar(table),
          token: null,
          joinedAt: now,
          disconnectedAt: null,
        };
      }
    }
    this.startGame(table);
  }

  private ensureChallengeVote(table: SharedTableState): void {
    const challenge = table.gameState?.pendingChallenge;
    if (challenge == null) {
      table.challengeVote = null;
      return;
    }
    const challengerPlayer =
      challenge.challengerPlayer ?? (challenge.responderPlayer + seatCount - 1) % seatCount;
    if (
      typeof challenge.animationEndsAt !== "number" ||
      !Number.isFinite(challenge.animationEndsAt)
    ) {
      challenge.animationEndsAt = Date.now() + challengeAnimationMs;
    }
    const current = table.challengeVote;
    if (
      current !== null &&
      current.targetTeam === challenge.targetTeam &&
      current.requestedValue === challenge.requestedValue &&
      current.challengerPlayer === challengerPlayer
    ) {
      return;
    }
    const participants = table.seats.flatMap((seat, seatIndex) =>
      seat?.kind === "human" && seatIndex % 2 === challenge.targetTeam
        ? [seatIndex]
        : [],
    );
    table.challengeVote = participants.length === 0
      ? null
      : createChallengeVote(
          crypto.randomUUID(),
          challenge.targetTeam,
          challenge.requestedValue,
          challengerPlayer,
          participants,
          Date.now(),
          seatCount,
        );
  }

  private resolveChallengeVote(
    table: SharedTableState,
    decidingSeatIndex: number,
    now: number,
  ): void {
    const vote = table.challengeVote;
    const game = table.gameState;
    if (vote === null || game?.pendingChallenge == null) return;
    const decision = challengeVoteDecision(vote, now);
    table.updatedAt = now;
    if (decision === "pending") {
      if (vote.participantSeatIndexes.length === 0) {
        table.challengeVote = null;
        table.nextActionAt = this.nextActionAt(table, this.activeHumanSeats());
      }
      return;
    }

    if (decision === "raise") {
      raisePendingChallenge(game, decidingSeatIndex, now);
    } else if (decision === "accept") {
      acceptPendingChallenge(game, now);
    } else {
      foldPendingChallenge(game, now);
    }
    table.challengeVote = null;
    this.ensureChallengeVote(table);
    table.nextActionAt = this.nextActionAt(table, this.activeHumanSeats());
  }

  private async canResume(request: Request, tableNumber?: number): Promise<Response> {
    const payload = (await request.json().catch(() => ({}))) as {
      playerToken?: string;
    };
    const table = await this.load(tableNumber);
    const seatIndex = table.seats.findIndex(
      (seat) => seat?.kind === "human" && seat.token === payload.playerToken,
    );
    return Response.json({
      canResume: seatIndex >= 0 && table.phase !== "empty",
      phase: table.phase,
    });
  }

  private async declineResume(request: Request, tableNumber?: number): Promise<Response> {
    const payload = (await request.json().catch(() => ({}))) as {
      playerToken?: string;
    };
    const table = await this.load(tableNumber);
    const seatIndex = table.seats.findIndex(
      (seat) => seat?.kind === "human" && seat.token === payload.playerToken,
    );
    if (seatIndex < 0) {
      return Response.json({ declined: false, tableClosed: table.phase === "empty" });
    }

    for (const socket of this.ctx.getWebSockets(`seat:${seatIndex}`)) {
      socket.close(4001, "Jogador decidiu nÃ£o voltar");
    }
    const now = Date.now();
    if (table.phase === "playing") {
      table.seats[seatIndex] = {
        kind: "bot",
        name: `RobÃ´ substituto ${seatIndex + 1}`,
        photoUrl: randomBotAvatar(table),
        token: null,
        joinedAt: now,
        disconnectedAt: null,
      };
      if (
        table.challengeVote !== null &&
        removeChallengeVoteParticipant(table.challengeVote, seatIndex)
      ) {
        this.resolveChallengeVote(table, seatIndex, now);
      }
    } else {
      if (table.fillBotsVote?.participantSeatIndexes.includes(seatIndex)) {
        table.fillBotsVote = null;
      }
      table.seats[seatIndex] = null;
      table.waitingStartAt = null;
    }

    const hasHuman = table.seats.some((seat) => seat?.kind === "human");
    if (!hasHuman) {
      for (const socket of this.ctx.getWebSockets()) {
        socket.close(4002, "Mesa encerrada");
      }
      await this.ctx.storage.deleteAlarm();
      await this.ctx.storage.deleteAll();
      await this.publishLobby(emptyTableState(table.tableNumber));
      return Response.json({ declined: true, tableClosed: true });
    }

    table.updatedAt = now;
    table.nextActionAt =
      table.phase === "playing"
        ? this.nextActionAt(table, this.activeHumanSeats())
        : null;
    await this.saveAndSchedule(table, true);
    this.broadcast(table);
    return Response.json({ declined: true, tableClosed: false });
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
    server.serializeAttachment({
      role: "player",
      token,
      seatIndex,
      connectedAt: Date.now(),
    });
    for (const oldSocket of this.ctx.getWebSockets(`seat:${seatIndex}`)) {
      if (oldSocket !== server) oldSocket.close(4000, "Conexão substituída");
    }
    table.seats[seatIndex]!.disconnectedAt = null;
    table.updatedAt = Date.now();
    if (table.phase === "playing") {
      table.nextActionAt = this.nextActionAt(table, this.activeHumanSeats());
    } else if (table.phase === "waiting") {
      this.syncWaitingCountdown(table, table.updatedAt, this.activeHumanSeats());
    }
    await this.saveAndSchedule(table, true);
    server.send(JSON.stringify(this.roomMessage(table, seatIndex)));
    this.broadcast(table, server);
    return new Response(null, { status: 101, webSocket: client });
  }

  private async connectSpectatorSocket(request: Request): Promise<Response> {
    if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
      return new Response("WebSocket obrigatório", { status: 426 });
    }
    const table = await this.load();
    if (
      table.phase !== "playing" ||
      table.gameState === null ||
      table.gameState.phase === "gameOver"
    ) {
      return new Response("Partida encerrada", { status: 409 });
    }
    const token = new URL(request.url).searchParams.get("token");
    if (!token) return new Response("Sessão inválida", { status: 403 });

    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);
    this.ctx.acceptWebSocket(server, [`spectator:${token}`]);
    server.serializeAttachment({
      role: "spectator",
      token,
      seatIndex: -1,
      connectedAt: Date.now(),
    });
    for (const oldSocket of this.ctx.getWebSockets(`spectator:${token}`)) {
      if (oldSocket !== server) oldSocket.close(4000, "Conexão substituída");
    }
    server.send(JSON.stringify(this.spectatorRoomMessage(table)));
    this.broadcast(table, server);
    return new Response(null, { status: 101, webSocket: client });
  }

  private async markDisconnected(socket: WebSocket): Promise<void> {
    const attachment = socket.deserializeAttachment() as SocketAttachment | null;
    if (!attachment || attachment.role === "spectator") return;
    const table = await this.load();
    if (!this.validHuman(table, attachment.seatIndex, attachment.token)) return;
    if (this.activeHumanSeats().has(attachment.seatIndex)) return;
    table.seats[attachment.seatIndex]!.disconnectedAt = Date.now();
    if (table.phase === "waiting") {
      table.waitingStartAt = null;
      if (table.fillBotsVote?.participantSeatIndexes.includes(attachment.seatIndex)) {
        table.fillBotsVote = null;
      }
    }
    if (
      table.phase === "playing" &&
      (table.gameState?.phase === "gameOver" ||
        table.challengeVote?.participantSeatIndexes.includes(
          attachment.seatIndex,
        ) ||
        this.expectedHumanSeat(table) === attachment.seatIndex)
    ) {
      table.nextActionAt = this.nextActionAt(table, this.activeHumanSeats());
    }
    table.updatedAt = Date.now();
    await this.saveAndSchedule(table, true);
    this.broadcast(table, socket);
  }

  private startGame(table: SharedTableState): void {
    table.phase = "playing";
    table.gameState = createInitialGame();
    table.waitingStartAt = null;
    table.fillBotsVote = null;
    table.challengeVote = null;
    table.updatedAt = Date.now();
    table.nextActionAt = this.nextActionAt(table, this.activeHumanSeats());
  }

  private returnToWaitingRoom(table: SharedTableState, now: number): void {
    table.phase = "waiting";
    table.gameState = null;
    table.nextActionAt = null;
    table.waitingStartAt = null;
    table.fillBotsVote = null;
    table.challengeVote = null;
    table.seats = table.seats.map((seat) =>
      seat?.kind === "human" ? seat : null,
    );
    table.updatedAt = now;
  }

  private entry(table: SharedTableState, seatIndex: number): Record<string, unknown> {
    return {
      tableNumber: String(table.tableNumber),
      playerToken: table.seats[seatIndex]!.token,
      seatIndex,
      phase: table.phase,
      seats: publicSeats(table),
      gameState: table.gameState,
      waitingStartAt: table.waitingStartAt,
      fillBotsVote: table.fillBotsVote,
      fillBotsVotingVersion,
      challengeVote: table.challengeVote,
      challengeVotingVersion,
      spectatorCount: this.spectatorCount(),
      status: this.status(table),
    };
  }

  private status(table: SharedTableState): LobbyTableStatus {
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
      waitingStartAt: table.waitingStartAt,
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
      waitingStartAt: table.waitingStartAt,
      fillBotsVote: table.fillBotsVote,
      fillBotsVotingVersion,
      challengeVote: table.challengeVote,
      challengeVotingVersion,
      spectatorCount: this.spectatorCount(),
    };
  }

  private spectatorRoomMessage(table: SharedTableState): Record<string, unknown> {
    return {
      type: "room",
      phase: table.phase,
      tableNumber: String(table.tableNumber),
      seatIndex: 0,
      spectator: true,
      spectatorCount: this.spectatorCount(),
      spectatorHandCounts: spectatorHandCounts(table.gameState),
      seats: publicSeats(table),
      gameState: spectatorGameState(table.gameState),
      waitingStartAt: null,
      fillBotsVote: null,
      fillBotsVotingVersion: 0,
      challengeVote: null,
      challengeVotingVersion: 0,
    };
  }

  private broadcast(table: SharedTableState, except?: WebSocket): void {
    for (const socket of this.ctx.getWebSockets()) {
      if (socket === except || socket.readyState !== WebSocket.OPEN) continue;
      const attachment = socket.deserializeAttachment() as SocketAttachment | null;
      if (!attachment) continue;
      socket.send(JSON.stringify(
        attachment.role === "spectator"
          ? this.spectatorRoomMessage(table)
          : this.roomMessage(table, attachment.seatIndex),
      ));
    }
  }

  private activeHumanSeats(): Set<number> {
    const active = new Set<number>();
    for (const socket of this.ctx.getWebSockets()) {
      if (socket.readyState !== WebSocket.OPEN) continue;
      const attachment = socket.deserializeAttachment() as SocketAttachment | null;
      if (!attachment || attachment.role === "spectator") continue;
      active.add(attachment.seatIndex);
    }
    return active;
  }

  private spectatorCount(): number {
    return this.ctx.getWebSockets().filter((socket) => {
      if (socket.readyState !== WebSocket.OPEN) return false;
      const attachment = socket.deserializeAttachment() as SocketAttachment | null;
      return attachment?.role === "spectator";
    }).length;
  }

  private closeSpectators(): void {
    for (const socket of this.ctx.getWebSockets()) {
      if (socket.readyState !== WebSocket.OPEN) continue;
      const attachment = socket.deserializeAttachment() as SocketAttachment | null;
      if (attachment?.role === "spectator") {
        socket.close(4004, "Partida encerrada");
      }
    }
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
      return false;
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
    if (!game) return null;
    const now = Date.now();
    if (game.phase === "gameOver") return now + 5000;
    if (game.challengeNotice !== null && game.phase !== "handFinished") {
      return Math.max(
        now,
        game.challengeNoticeUntil ?? now + challengeNoticeMs,
      );
    }
    if (engineDelayMs !== undefined && engineDelayMs !== null) {
      const expectedHuman = this.expectedHumanSeat(table);
      if (expectedHuman === null || !activeHumans.has(expectedHuman)) {
        return now + Math.max(engineDelayMs, 2000);
      }
    }
    if (game.awaitingNextTrick) {
      return now + handTransitionMs;
    }
    if (game.phase === "handFinished") {
      const transitionAt = now +
        (game.matchWinner === null
          ? betweenPartidasTransitionMs
          : handTransitionMs);
      return game.challengeNotice !== null
        ? Math.max(transitionAt, game.challengeNoticeUntil ?? transitionAt)
        : transitionAt;
    }
    if (game.pendingChallenge !== null && table.challengeVote !== null) {
      return table.challengeVote.expiresAt;
    }
    const expectedHuman = this.expectedHumanSeat(table);
    if (expectedHuman !== null && activeHumans.has(expectedHuman)) {
      return now + humanTurnMs;
    }
    if (expectedHuman !== null) {
      const disconnectedAt = table.seats[expectedHuman]?.disconnectedAt ?? now;
      return disconnectedAt + disconnectGraceMs;
    }
    return now + 2000;
  }

  private allHumansPastGrace(table: SharedTableState, now: number): boolean {
    return table.seats.every(
      (seat) =>
        seat?.kind !== "human" ||
        (seat.disconnectedAt !== null && now - seat.disconnectedAt >= disconnectGraceMs),
    );
  }

  private syncWaitingCountdown(
    table: SharedTableState,
    now: number,
    activeHumans: Set<number>,
  ): void {
    const sixConnectedHumans =
      activeHumans.size === seatCount &&
      table.seats.every((seat) => seat?.kind === "human");
    if (!sixConnectedHumans) {
      table.waitingStartAt = null;
      return;
    }
    table.fillBotsVote = null;
    table.waitingStartAt ??= now + 5000;
    if (now >= table.waitingStartAt) this.startGame(table);
  }

  private validHuman(table: SharedTableState, seatIndex: number, token: string): boolean {
    const seat = table.seats[seatIndex];
    return seat?.kind === "human" && seat.token === token;
  }

  private async load(requestedTableNumber?: number): Promise<SharedTableState> {
    const stored = await this.ctx.storage.get<SharedTableState>("table");
    if (stored?.version === 2) {
      stored.waitingStartAt ??= null;
      stored.fillBotsVote ??= null;
      stored.challengeVote ??= null;
      if (
        stored.fillBotsVote !== null &&
        (typeof stored.fillBotsVote.id !== "string" ||
          !Array.isArray(stored.fillBotsVote.shownAt))
      ) {
        stored.fillBotsVote = null;
      }
      if (
        stored.challengeVote !== null &&
        (typeof stored.challengeVote.id !== "string" ||
          typeof stored.challengeVote.expiresAt !== "number" ||
          !Number.isFinite(stored.challengeVote.expiresAt))
      ) {
        stored.challengeVote = null;
      }
      this.ensureChallengeVote(stored);
      return stored;
    }
    const tableNumber = requestedTableNumber ?? 1;
    return emptyTableState(tableNumber);
  }

  private async saveAndSchedule(
    table: SharedTableState,
    notifyLobby = false,
  ): Promise<void> {
    await this.ctx.storage.put("table", table);
    const now = Date.now();
    const deadlines = [
      table.nextActionAt,
      table.waitingStartAt,
      table.fillBotsVote?.expiresAt ?? null,
      table.challengeVote?.expiresAt ?? null,
    ].filter(
      (value): value is number => value !== null,
    );
    const needsDisconnectedDeadlines =
      table.phase === "waiting" || table.gameState?.phase === "gameOver";
    if (needsDisconnectedDeadlines) {
      for (const seat of table.seats) {
        if (seat?.kind === "human" && seat.disconnectedAt !== null) {
          const seatIndex = table.seats.indexOf(seat);
          if (
            table.fillBotsVote?.participantSeatIndexes.includes(seatIndex) &&
            table.fillBotsVote.expiresAt === null
          ) continue;
          deadlines.push(seat.disconnectedAt + disconnectGraceMs);
        }
      }
    }
    if (deadlines.length === 0) {
      await this.ctx.storage.deleteAlarm();
    } else {
      await this.ctx.storage.setAlarm(Math.max(now, Math.min(...deadlines)));
    }
    if (notifyLobby) await this.publishLobby(table);
  }

  private async publishLobby(table: SharedTableState): Promise<void> {
    try {
      await lobbyStub(this.env).fetch(
        new Request("https://lobby.internal/update", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(this.status(table)),
        }),
      );
    } catch (error) {
      console.error("Não foi possível atualizar o lobby.", error);
    }
  }

  private async clearTable(tableNumber: number): Promise<void> {
    await this.ctx.storage.deleteAlarm();
    await this.ctx.storage.deleteAll();
    await this.publishLobby(emptyTableState(tableNumber));
  }
}

function tableStub(env: Env, tableNumber: number): DurableObjectStub<GameTable> {
  return env.GAME_TABLES.getByName(`fixed-table-${tableNumber}`);
}

function lobbyStub(env: Env): DurableObjectStub<GameLobby> {
  return env.LOBBY.getByName("fixed-lobby");
}

function emptyTableState(tableNumber: number): SharedTableState {
  return {
    version: 2,
    tableNumber,
    phase: "empty",
    seats: Array.from({ length: seatCount }, () => null),
    gameState: null,
    nextActionAt: null,
    waitingStartAt: null,
    fillBotsVote: null,
    challengeVote: null,
    updatedAt: Date.now(),
  };
}

function spectatorGameState(gameState: GameState | null): GameState | null {
  if (gameState === null) return null;
  return {
    ...gameState,
    playerHands: gameState.playerHands.map(() => []),
    hiddenCards: gameState.hiddenCards?.map(() => []),
  };
}

function spectatorHandCounts(gameState: GameState | null): number[] {
  if (gameState === null) return Array<number>(seatCount).fill(0);
  return gameState.playerHands.map((hand) => hand.length);
}

function publicSeats(table: SharedTableState): Array<Record<string, unknown> | null> {
  return table.seats.map((seat, index) =>
    seat === null
      ? null
      : {
          index,
          kind: seat.kind,
          name: seat.name,
          photoUrl:
            seat.kind === "bot"
              ? seat.photoUrl ?? fallbackBotAvatar(table.tableNumber, index)
              : seat.photoUrl ?? null,
          team: index % 2,
          connected: seat.kind === "bot" || seat.disconnectedAt === null,
        },
  );
}

function connectionUrl(
  requestUrl: URL,
  tableNumber: number,
  token: string,
  operation = "connect",
): string {
  const protocol = requestUrl.protocol === "https:" ? "wss:" : "ws:";
  return `${protocol}//${requestUrl.host}/api/tables/${tableNumber}/${operation}?token=${encodeURIComponent(token)}`;
}

function cleanPlayerName(value: string | undefined, seatIndex: number): string {
  const clean = value?.trim().replace(/\s+/g, " ").slice(0, 20);
  return clean ? clean : `Jogador ${seatIndex + 1}`;
}

function cleanPhotoUrl(value: string | null | undefined): string | null {
  if (!value || value.length > 2048) return null;
  try {
    const url = new URL(value);
    return url.protocol === "https:" ? url.toString() : null;
  } catch {
    return null;
  }
}

function botAvatarAsset(number: number): string {
  return `assets/images/avatar/robos/robo_${String(number).padStart(2, "0")}.png`;
}

function randomBotAvatar(table: SharedTableState): string {
  const used = new Set(
    table.seats
      .filter((seat) => seat?.kind === "bot")
      .map((seat) => seat?.photoUrl)
      .filter((value): value is string => typeof value === "string"),
  );
  const available = Array.from({ length: botAvatarCount }, (_, index) => index + 1)
    .map(botAvatarAsset)
    .filter((asset) => !used.has(asset));
  const choices = available.length > 0
    ? available
    : Array.from({ length: botAvatarCount }, (_, index) => botAvatarAsset(index + 1));
  const randomValue = crypto.getRandomValues(new Uint32Array(1))[0];
  return choices[randomValue % choices.length];
}

function fallbackBotAvatar(tableNumber: number, seatIndex: number): string {
  return botAvatarAsset(((tableNumber * 3 + seatIndex * 7) % botAvatarCount) + 1);
}

async function readSmallBody(request: Request): Promise<string | null> {
  const declaredLength = Number(request.headers.get("Content-Length"));
  if (Number.isFinite(declaredLength) && declaredLength > 16_384) return null;
  const body = await request.text();
  return new TextEncoder().encode(body).byteLength <= 16_384 ? body : null;
}

function parseRecord(value: string): Record<string, unknown> | null {
  try {
    const parsed = JSON.parse(value) as unknown;
    return parsed !== null && typeof parsed === "object" && !Array.isArray(parsed)
      ? (parsed as Record<string, unknown>)
      : null;
  } catch {
    return null;
  }
}

function isChallengeVoteChoice(value: unknown): value is ChallengeVoteChoice {
  return value === "accept" || value === "fold" || value === "raise";
}
