export type MatchPhase = "playing" | "handFinished" | "gameOver";

export interface PlayedCardState {
  playerIndex: number;
  card: string;
}

export interface ChallengeState {
  challengerTeam: number;
  targetTeam: number;
  requestedValue: number;
  responderPlayer: number;
}

export interface GameState {
  version: number;
  scores: number[];
  playerHands: string[][];
  currentTrick: PlayedCardState[];
  playedCards: PlayedCardState[];
  trickWinners: Array<number | null>;
  history: string[];
  tenDecisionMade: boolean[];
  botChallengeConsideredThisTrick: boolean[];
  automaticTimeouts: number[];
  dealerIndex: number;
  trickLeaderIndex: number;
  currentPlayerIndex: number;
  handValue: number;
  nextTrickLeader: number | null;
  matchWinner: number | null;
  lastChallengeTeam: number | null;
  lastHandWinner: number | null;
  lastHandPoints: number;
  lastCompletedHandNumber: number;
  lastCompletedHandWinnerTeam: number | null;
  awaitingNextTrick: boolean;
  challengeAttemptedThisTurn: boolean;
  phase: MatchPhase;
  pendingChallenge: ChallengeState | null;
  challengeNotice: string | null;
  challengeNoticeAccepted: boolean;
  statusMessage: string;
}

export interface BotStep {
  state: GameState;
  nextDelayMs: number | null;
}

const ranks = ["4", "5", "6", "7", "Q", "J", "K", "A", "2", "3"];
const suits = ["o", "e", "c", "p"];

export const fullDeck = (): string[] =>
  ranks.flatMap((rank) => suits.map((suit) => `${rank}${suit}`));

export function createInitialGame(
  firstPlayerIndex = randomPlayerIndex(),
): GameState {
  const game: GameState = {
    version: 1,
    scores: [0, 0],
    playerHands: Array.from({ length: 6 }, () => [] as string[]),
    currentTrick: [],
    playedCards: [],
    trickWinners: [],
    history: [],
    tenDecisionMade: [true, true],
    botChallengeConsideredThisTrick: [false, false],
    automaticTimeouts: [0, 0, 0, 0, 0, 0],
    // dealHand gira o carteador antes de distribuir. Esta posição faz com que
    // a cadeira sorteada seja a primeira a jogar após esse giro.
    dealerIndex: (firstPlayerIndex + 4) % 6,
    trickLeaderIndex: firstPlayerIndex,
    currentPlayerIndex: firstPlayerIndex,
    handValue: 1,
    nextTrickLeader: null,
    matchWinner: null,
    lastChallengeTeam: null,
    lastHandWinner: null,
    lastHandPoints: 0,
    lastCompletedHandNumber: 0,
    lastCompletedHandWinnerTeam: null,
    awaitingNextTrick: false,
    challengeAttemptedThisTurn: false,
    phase: "playing",
    pendingChallenge: null,
    challengeNotice: null,
    challengeNoticeAccepted: false,
    statusMessage: "",
  };
  dealHand(game);
  return game;
}

function randomPlayerIndex(): number {
  const random = new Uint32Array(1);
  crypto.getRandomValues(random);
  return random[0] % 6;
}

export function cardStrength(code: string): number {
  const manilha: Record<string, number> = {
    Qo: 19,
    Jp: 18,
    "2p": 17,
    Ap: 16,
    "5p": 15,
    "4p": 14,
    "7c": 13,
    Ae: 12,
    "7o": 11,
  };
  if (manilha[code] !== undefined) return manilha[code];
  const common: Record<string, number> = {
    "3": 10,
    "2": 9,
    A: 8,
    K: 7,
    J: 6,
    Q: 5,
    "7": 4,
    "6": 3,
    "5": 2,
    "4": 1,
  };
  return common[code.slice(0, -1)] ?? 1;
}

export function scorePoints(handValue: number): number {
  return ({ 1: 2, 2: 4, 3: 6, 4: 8, 6: 12 } as Record<number, number>)[handValue] ??
    handValue * 2;
}

export function isGameState(value: unknown): value is GameState {
  if (!value || typeof value !== "object") return false;
  const state = value as Partial<GameState>;
  return (
    state.version === 1 &&
    Array.isArray(state.scores) &&
    state.scores.length === 2 &&
    Array.isArray(state.playerHands) &&
    state.playerHands.length === 6 &&
    Array.isArray(state.currentTrick) &&
    Array.isArray(state.playedCards) &&
    Array.isArray(state.trickWinners) &&
    ["playing", "handFinished", "gameOver"].includes(state.phase ?? "")
  );
}

export function advanceBot(state: GameState): BotStep {
  const game = structuredClone(state);

  if (game.challengeNotice !== null) {
    game.challengeNotice = null;
    game.challengeNoticeAccepted = false;
    return { state: game, nextDelayMs: 100 };
  }

  if (game.phase === "gameOver") return { state: game, nextDelayMs: null };

  if (game.phase === "handFinished") {
    if (game.matchWinner !== null) {
      game.phase = "gameOver";
      setStatus(game, `${teamLabel(game.matchWinner)} venceu a partida!`);
      return { state: game, nextDelayMs: null };
    }
    dealHand(game);
    return { state: game, nextDelayMs: 650 };
  }

  if (game.awaitingNextTrick) {
    beginNextTrick(game);
    return { state: game, nextDelayMs: 650 };
  }

  if (game.pendingChallenge !== null) {
    acceptPendingChallenge(game);
    return { state: game, nextDelayMs: 650 };
  }

  const tenTeam = pendingTenTeam(game);
  if (tenTeam !== null) {
    game.tenDecisionMade[tenTeam] = true;
    setStatus(game, `${teamLabel(tenTeam)} decidiu jogar a mão de dez.`);
    return { state: game, nextDelayMs: 650 };
  }

  const playerIndex = game.currentPlayerIndex;
  if (playerIndex < 0 || playerIndex >= game.playerHands.length) {
    return { state: game, nextDelayMs: 650 };
  }
  const card = chooseBotCard(game, playerIndex);
  if (card === null) return { state: game, nextDelayMs: null };
  playCard(game, playerIndex, card);
  const delay =
    (game as GameState).phase === "handFinished" || game.awaitingNextTrick ? 5000 : 650;
  return { state: game, nextDelayMs: delay };
}

export function pendingTenTeam(game: GameState): number | null {
  if (game.scores[0] === 10 && game.scores[1] === 10) return null;
  if (game.scores[0] === 10 && !game.tenDecisionMade[0]) return 0;
  if (game.scores[1] === 10 && !game.tenDecisionMade[1]) return 1;
  return null;
}

function acceptPendingChallenge(game: GameState): void {
  const challenge = game.pendingChallenge;
  if (challenge === null) return;
  game.handValue = challenge.requestedValue;
  game.pendingChallenge = null;
  game.challengeNotice = null;
  game.challengeNoticeAccepted = false;
  setStatus(game, `${teamLabel(challenge.targetTeam)} aceitou o desafio.`);
}

function chooseBotCard(game: GameState, playerIndex: number): string | null {
  const cards = [...game.playerHands[playerIndex]].sort(
    (a, b) => cardStrength(a) - cardStrength(b),
  );
  if (cards.length === 0) return null;
  if (game.currentTrick.length === 0) {
    if (game.trickWinners.length > 0 && game.trickWinners[0] === playerIndex % 2) {
      return cards[0];
    }
    return cards[Math.min(1, cards.length - 1)];
  }
  const topStrength = Math.max(...game.currentTrick.map((play) => cardStrength(play.card)));
  const topTeams = new Set(
    game.currentTrick
      .filter((play) => cardStrength(play.card) === topStrength)
      .map((play) => play.playerIndex % 2),
  );
  if (topTeams.size === 1 && topTeams.has(playerIndex % 2)) return cards[0];
  return cards.find((card) => cardStrength(card) > topStrength) ?? cards[0];
}

function playCard(game: GameState, playerIndex: number, card: string): void {
  const hand = game.playerHands[playerIndex];
  const cardIndex = hand.indexOf(card);
  if (cardIndex < 0) return;
  hand.splice(cardIndex, 1);
  const play = { playerIndex, card };
  game.currentTrick.push(play);
  game.playedCards.push(play);
  setStatus(game, `Robô substituto jogou ${card}.`);

  if (game.currentTrick.length === 6) {
    finishTrick(game);
    return;
  }
  game.currentPlayerIndex = (playerIndex + 1) % 6;
  game.challengeAttemptedThisTurn = false;
}

function finishTrick(game: GameState): void {
  const winner = resolveTrickWinner(game.currentTrick);
  const winningTeam = winner === null ? null : winner % 2;
  game.trickWinners.push(winningTeam);
  game.lastCompletedHandNumber = game.trickWinners.length;
  game.lastCompletedHandWinnerTeam = winningTeam;
  game.nextTrickLeader = winner ?? game.trickLeaderIndex;
  setStatus(
    game,
    winningTeam === null
      ? `A ${game.trickWinners.length}ª mão empatou.`
      : `${teamLabel(winningTeam)} venceu a ${game.trickWinners.length}ª mão.`,
  );

  const disputeWinner = resolveDisputeWinner(game.trickWinners);
  if (disputeWinner !== null) {
    finishHand(game, disputeWinner);
  } else if (game.trickWinners.length === 3) {
    game.pendingChallenge = null;
    game.awaitingNextTrick = false;
    game.lastHandWinner = null;
    game.lastHandPoints = 0;
    game.phase = "handFinished";
    setStatus(game, "As três mãos empataram. Nenhum trio ganhou tentos.");
  } else {
    game.awaitingNextTrick = true;
    game.currentPlayerIndex = -1;
  }
}

export function resolveTrickWinner(plays: PlayedCardState[]): number | null {
  if (plays.length === 0) return null;
  const maximum = Math.max(...plays.map((play) => cardStrength(play.card)));
  const strongest = plays.filter((play) => cardStrength(play.card) === maximum);
  const teams = new Set(strongest.map((play) => play.playerIndex % 2));
  return teams.size === 1 ? strongest[0].playerIndex : null;
}

export function resolveDisputeWinner(results: Array<number | null>): number | null {
  if (results.length < 2) return null;
  const [first, second] = results;
  if (first === null && second !== null) return second;
  if (first !== null && (second === first || second === null)) return first;
  if (results.length < 3) return null;
  const third = results[2];
  if (third !== null) return third;
  return first ?? second ?? null;
}

function beginNextTrick(game: GameState): void {
  game.currentTrick = [];
  game.awaitingNextTrick = false;
  game.lastCompletedHandNumber = 0;
  game.lastCompletedHandWinnerTeam = null;
  game.trickLeaderIndex = game.nextTrickLeader ?? game.trickLeaderIndex;
  game.currentPlayerIndex = game.trickLeaderIndex;
  game.challengeAttemptedThisTurn = false;
  game.botChallengeConsideredThisTrick = [false, false];
  setStatus(game, `Robô ${game.currentPlayerIndex} começa a próxima mão.`);
}

function finishHand(game: GameState, winningTeam: number): void {
  const points = scorePoints(game.handValue);
  game.pendingChallenge = null;
  game.awaitingNextTrick = false;
  game.scores[winningTeam] += points;
  game.lastHandWinner = winningTeam;
  game.lastHandPoints = points;
  if (game.scores[winningTeam] >= 12) game.matchWinner = winningTeam;
  game.phase = "handFinished";
  setStatus(game, `${teamLabel(winningTeam)} ganhou ${points} pontos.`);
}

function dealHand(game: GameState): void {
  game.dealerIndex = (game.dealerIndex + 1) % 6;
  game.phase = "playing";
  game.pendingChallenge = null;
  game.challengeNotice = null;
  game.challengeNoticeAccepted = false;
  game.matchWinner = null;
  game.lastChallengeTeam = null;
  game.lastHandWinner = null;
  game.lastHandPoints = 0;
  game.lastCompletedHandNumber = 0;
  game.lastCompletedHandWinnerTeam = null;
  game.currentTrick = [];
  game.playedCards = [];
  game.trickWinners = [];
  game.awaitingNextTrick = false;
  game.nextTrickLeader = null;
  game.challengeAttemptedThisTurn = false;
  game.botChallengeConsideredThisTrick = [false, false];

  const deck = shuffle(fullDeck());
  game.playerHands = Array.from({ length: 6 }, () => [] as string[]);
  for (let round = 0; round < 3; round += 1) {
    for (let offset = 1; offset <= 6; offset += 1) {
      const playerIndex = (game.dealerIndex + offset) % 6;
      game.playerHands[playerIndex].push(deck.pop()!);
    }
  }
  game.trickLeaderIndex = (game.dealerIndex + 1) % 6;
  game.currentPlayerIndex = game.trickLeaderIndex;
  const tenToTen = game.scores[0] === 10 && game.scores[1] === 10;
  const tenHand = game.scores[0] === 10 || game.scores[1] === 10;
  game.handValue = tenHand ? 2 : 1;
  game.tenDecisionMade = [
    tenToTen || game.scores[0] !== 10,
    tenToTen || game.scores[1] !== 10,
  ];
  setStatus(game, tenHand ? "Mão de dez: sem desafios, valendo 4." : "Nova disputa.");
}

function shuffle<T>(values: T[]): T[] {
  for (let index = values.length - 1; index > 0; index -= 1) {
    const random = new Uint32Array(1);
    crypto.getRandomValues(random);
    const target = random[0] % (index + 1);
    [values[index], values[target]] = [values[target], values[index]];
  }
  return values;
}

function setStatus(game: GameState, message: string): void {
  game.statusMessage = message;
  game.history.unshift(message);
  if (game.history.length > 30) game.history.length = 30;
}

function teamLabel(team: number): string {
  return team === 0 ? "Trio Azul" : "Trio Dourado";
}
