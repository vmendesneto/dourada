export type MatchPhase = "playing" | "handFinished" | "gameOver";

export interface PlayedCardState {
  playerIndex: number;
  card: string;
  hidden?: boolean;
}

export interface ChallengeState {
  challengerTeam: number;
  challengerPlayer?: number;
  targetTeam: number;
  requestedValue: number;
  responderPlayer: number;
  animationEndsAt?: number;
}

export interface GameState {
  version: number;
  perspectiveTeam?: number;
  scores: number[];
  playerHands: string[][];
  hiddenCards?: string[][];
  currentTrick: PlayedCardState[];
  playedCards: PlayedCardState[];
  trickWinners: Array<number | null>;
  history: string[];
  tenDecisionMade: boolean[];
  botChallengeConsideredThisTrick: boolean[];
  automaticTimeouts: number[];
  signalEmojisByTeam?: string[][];
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
  challengeNoticeUntil?: number | null;
  statusMessage: string;
}

export interface BotStep {
  state: GameState;
  nextDelayMs: number | null;
}

export const handTransitionMs = 2000;
export const partidaStartDelayMs = 1500;
export const challengeAnimationMs = 2780;
export const challengeNoticeMs = 2000;
export const betweenPartidasTransitionMs =
  handTransitionMs + partidaStartDelayMs;

const ranks = ["4", "5", "6", "7", "Q", "J", "K", "A", "2", "3"];
const suits = ["o", "e", "c", "p"];
export const signalEmojiPool = [
  "😶",
  "😉",
  "😮",
  "😎",
  "🤨",
  "😬",
  "😏",
  "😡",
  "🤩",
];

export const fullDeck = (): string[] =>
  ranks.flatMap((rank) => suits.map((suit) => `${rank}${suit}`));

export function createInitialGame(
  firstPlayerIndex = randomPlayerIndex(),
): GameState {
  const game: GameState = {
    version: 1,
    perspectiveTeam: 0,
    scores: [0, 0],
    playerHands: Array.from({ length: 6 }, () => [] as string[]),
    hiddenCards: Array.from({ length: 6 }, () => [] as string[]),
    currentTrick: [],
    playedCards: [],
    trickWinners: [],
    history: [],
    tenDecisionMade: [true, true],
    botChallengeConsideredThisTrick: [false, false],
    automaticTimeouts: [0, 0, 0, 0, 0, 0],
    signalEmojisByTeam: shuffledSignalEmojisByTeam(),
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
    challengeNoticeUntil: null,
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

export function cardDisplayName(code: string): string {
  const rank = code.slice(0, -1);
  const suit = code.slice(-1);
  const rankName: Record<string, string> = {
    A: "Ás",
    K: "Rei",
    Q: "Dama",
    J: "Valete",
    "7": "7",
    "6": "6",
    "5": "5",
    "4": "4",
    "3": "3",
    "2": "2",
  };
  const suitName: Record<string, string> = {
    o: "Ouros",
    e: "Espadas",
    c: "Copas",
    p: "Paus",
  };
  if (rankName[rank] === undefined || suitName[suit] === undefined) return code;

  const name = `${rankName[rank]} de ${suitName[suit]}`;
  const nickname: Record<string, string> = {
    Qo: "Douradinha",
    Jp: "Valetinho",
    "2p": "Dunguinha",
    Ap: "Azinho",
    "5p": "Cinquinho",
    "4p": "Zap",
    Ae: "Espadilha",
  };
  return nickname[code] === undefined ? name : `${name} (${nickname[code]})`;
}

export function scorePoints(handValue: number): number {
  return (
    ({ 1: 2, 2: 4, 3: 6, 4: 8, 6: 12 } as Record<number, number>)[handValue] ??
    handValue * 2
  );
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
    (state.hiddenCards === undefined ||
      (Array.isArray(state.hiddenCards) &&
        state.hiddenCards.length === 6 &&
        state.hiddenCards.every(
          (cards) =>
            Array.isArray(cards) &&
            cards.length <= 1 &&
            cards.every((card) => typeof card === "string"),
        ))) &&
    Array.isArray(state.currentTrick) &&
    hasLegalHiddenDiscards(state.currentTrick, state.scores) &&
    Array.isArray(state.playedCards) &&
    Array.isArray(state.trickWinners) &&
    (state.signalEmojisByTeam === undefined ||
      isSignalEmojiMappings(state.signalEmojisByTeam)) &&
    (state.challengeNoticeUntil === undefined ||
      state.challengeNoticeUntil === null ||
      (typeof state.challengeNoticeUntil === "number" &&
        Number.isFinite(state.challengeNoticeUntil))) &&
    (state.pendingChallenge === null ||
      isChallengeState(state.pendingChallenge)) &&
    ["playing", "handFinished", "gameOver"].includes(state.phase ?? "")
  );
}

function isChallengeState(value: unknown): value is ChallengeState {
  if (value === null || typeof value !== "object") return false;
  const challenge = value as Partial<ChallengeState>;
  return (
    (challenge.challengerTeam === 0 || challenge.challengerTeam === 1) &&
    (challenge.targetTeam === 0 || challenge.targetTeam === 1) &&
    challenge.targetTeam !== challenge.challengerTeam &&
    [2, 3, 4, 6].includes(challenge.requestedValue ?? -1) &&
    Number.isInteger(challenge.responderPlayer) &&
    (challenge.responderPlayer ?? -1) >= 0 &&
    (challenge.responderPlayer ?? 6) < 6 &&
    (challenge.challengerPlayer === undefined ||
      (Number.isInteger(challenge.challengerPlayer) &&
        challenge.challengerPlayer >= 0 &&
        challenge.challengerPlayer < 6)) &&
    (challenge.animationEndsAt === undefined ||
      (typeof challenge.animationEndsAt === "number" &&
        Number.isFinite(challenge.animationEndsAt)))
  );
}

export function advanceBot(state: GameState): BotStep {
  const game = structuredClone(state);

  if (game.challengeNotice !== null) {
    game.challengeNotice = null;
    game.challengeNoticeAccepted = false;
    game.challengeNoticeUntil = null;
    return { state: game, nextDelayMs: 100 };
  }

  if (game.phase === "gameOver") return { state: game, nextDelayMs: null };

  if (game.phase === "handFinished") {
    if (game.matchWinner !== null) {
      game.phase = "gameOver";
      setStatus(game, `${teamWon(game, game.matchWinner, "a partida")}!`);
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
    if (
      currentTrickIsLockedAgainst(game, game.pendingChallenge.targetTeam)
    ) {
      foldPendingChallenge(game);
    } else {
      acceptPendingChallenge(game);
    }
    return { state: game, nextDelayMs: 650 };
  }

  const tenTeam = pendingTenTeam(game);
  if (tenTeam !== null) {
    game.tenDecisionMade[tenTeam] = true;
    const message =
      `${teamAction(game, tenTeam, "decidimos", "decidiram")} jogar a mão de dez.`;
    game.challengeNotice = message;
    game.challengeNoticeAccepted = true;
    game.challengeNoticeUntil = Date.now() + challengeNoticeMs;
    setStatus(game, message);
    return { state: game, nextDelayMs: challengeNoticeMs };
  }

  const playerIndex = game.currentPlayerIndex;
  if (playerIndex < 0 || playerIndex >= game.playerHands.length) {
    return { state: game, nextDelayMs: 650 };
  }
  const card = chooseBotCard(game, playerIndex);
  if (card === null) return { state: game, nextDelayMs: null };
  playCard(game, playerIndex, card);
  const delay = game.awaitingNextTrick
    ? handTransitionMs
    : (game as GameState).phase === "handFinished"
      ? game.matchWinner === null
        ? betweenPartidasTransitionMs
        : handTransitionMs
      : 650;
  return { state: game, nextDelayMs: delay };
}

export function pendingTenTeam(game: GameState): number | null {
  if (game.scores[0] === 10 && game.scores[1] === 10) return null;
  if (game.scores[0] === 10 && !game.tenDecisionMade[0]) return 0;
  if (game.scores[1] === 10 && !game.tenDecisionMade[1]) return 1;
  return null;
}

export function acceptPendingChallenge(
  game: GameState,
  now = Date.now(),
): boolean {
  const challenge = game.pendingChallenge;
  if (challenge === null) return false;
  game.handValue = challenge.requestedValue;
  game.pendingChallenge = null;
  const message =
    `${teamAction(game, challenge.targetTeam, "aceitamos", "aceitaram")} o desafio.`;
  game.challengeNotice = message;
  game.challengeNoticeAccepted = true;
  game.challengeNoticeUntil =
    Math.max(now, challenge.animationEndsAt ?? now) + challengeNoticeMs;
  setStatus(game, message);
  return true;
}

export function foldPendingChallenge(
  game: GameState,
  now = Date.now(),
): boolean {
  const challenge = game.pendingChallenge;
  if (challenge === null) return false;
  const message =
    `${teamAction(game, challenge.targetTeam, "corremos", "correram")} do desafio.`;
  finishHand(
    game,
    challenge.challengerTeam,
    message,
  );
  game.challengeNotice = message;
  game.challengeNoticeAccepted = false;
  game.challengeNoticeUntil =
    Math.max(now, challenge.animationEndsAt ?? now) + challengeNoticeMs;
  return true;
}

export function raisePendingChallenge(
  game: GameState,
  playerIndex: number,
  now = Date.now(),
): boolean {
  const challenge = game.pendingChallenge;
  if (
    challenge === null ||
    playerIndex < 0 ||
    playerIndex >= 6 ||
    playerIndex % 2 !== challenge.targetTeam
  ) {
    return false;
  }
  const requestedValue = nextChallengeAfter(challenge.requestedValue);
  if (requestedValue === null) return false;

  const raisingTeam = challenge.targetTeam;
  game.handValue = challenge.requestedValue;
  game.lastChallengeTeam = raisingTeam;
  game.pendingChallenge = {
    challengerTeam: raisingTeam,
    challengerPlayer: playerIndex,
    targetTeam: 1 - raisingTeam,
    requestedValue,
    responderPlayer: nextPlayerOnTeam(playerIndex, 1 - raisingTeam),
    animationEndsAt: now + challengeAnimationMs,
  };
  setStatus(
    game,
    `${teamAction(game, raisingTeam, "pedimos", "pediram")} ${challengeLabelForPoints(requestedValue)}`,
  );
  return true;
}

export function currentTrickIsLockedAgainst(
  game: GameState,
  team: number,
): boolean {
  const visibleTrick = game.currentTrick.filter((play) => !play.hidden);
  if (visibleTrick.length === 0) return false;

  const playersWhoAlreadyPlayed = new Set(
    game.currentTrick.map((play) => play.playerIndex),
  );
  const remainingTeamCards = game.playerHands.flatMap((hand, playerIndex) =>
    playerIndex % 2 === team && !playersWhoAlreadyPlayed.has(playerIndex)
      ? hand.map((card) => ({ playerIndex, card }))
      : [],
  );

  const disputeIsLostWith = (trick: PlayedCardState[]): boolean => {
    const provisionalWinner = resolveTrickWinner(trick);
    const provisionalTeam =
      provisionalWinner === null ? null : provisionalWinner % 2;
    const disputeWinner = resolveDisputeWinner([
      ...game.trickWinners,
      provisionalTeam,
    ]);
    return disputeWinner !== null && disputeWinner !== team;
  };

  if (remainingTeamCards.length === 0) {
    return disputeIsLostWith(game.currentTrick);
  }

  return remainingTeamCards.every(({ playerIndex, card }) =>
    disputeIsLostWith([
      ...game.currentTrick,
      { playerIndex, card },
    ]),
  );
}

function chooseBotCard(game: GameState, playerIndex: number): string | null {
  const cards = [...game.playerHands[playerIndex]].sort(
    (a, b) => cardStrength(a) - cardStrength(b),
  );
  if (cards.length === 0) return null;
  const visibleTrick = game.currentTrick.filter((play) => !play.hidden);
  if (visibleTrick.length === 0) {
    if (
      game.trickWinners.length > 0 &&
      game.trickWinners[0] === playerIndex % 2
    ) {
      return cards[0];
    }
    return cards[Math.min(1, cards.length - 1)];
  }
  const topStrength = Math.max(
    ...visibleTrick.map((play) => cardStrength(play.card)),
  );
  const topTeams = new Set(
    visibleTrick
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
  game.hiddenCards ??= Array.from({ length: 6 }, () => [] as string[]);
  const hiddenIndex = game.hiddenCards[playerIndex].indexOf(card);
  const canHide =
    !game.scores.includes(10) &&
    hiddenPlaysForTeam(game.currentTrick, playerIndex % 2) < 2;
  const hidden = hiddenIndex >= 0 && canHide;
  if (hiddenIndex >= 0) game.hiddenCards[playerIndex].splice(hiddenIndex, 1);
  const play: PlayedCardState = hidden
    ? { playerIndex, card, hidden: true }
    : { playerIndex, card };
  game.currentTrick.push(play);
  game.playedCards.push(play);
  setStatus(
    game,
    hidden
      ? "Robô substituto descartou uma carta fechada."
      : `Robô substituto jogou ${cardDisplayName(card)}.`,
  );

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
      : `${teamWon(game, winningTeam, `a ${game.trickWinners.length}ª mão`)}.`,
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
  const visiblePlays = plays.filter((play) => !play.hidden);
  if (visiblePlays.length === 0) return null;
  const maximum = Math.max(
    ...visiblePlays.map((play) => cardStrength(play.card)),
  );
  const strongest = visiblePlays.filter(
    (play) => cardStrength(play.card) === maximum,
  );
  const teams = new Set(strongest.map((play) => play.playerIndex % 2));
  return teams.size === 1 ? strongest[0].playerIndex : null;
}

export function resolveDisputeWinner(
  results: Array<number | null>,
): number | null {
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

function finishHand(
  game: GameState,
  winningTeam: number,
  reason?: string,
): void {
  const points = scorePoints(game.handValue);
  game.pendingChallenge = null;
  game.awaitingNextTrick = false;
  game.scores[winningTeam] += points;
  game.lastHandWinner = winningTeam;
  game.lastHandPoints = points;
  if (game.scores[winningTeam] >= 12) game.matchWinner = winningTeam;
  game.phase = "handFinished";
  setStatus(
    game,
    reason
      ? `${reason} ${teamScored(game, winningTeam, points)}`
      : teamScored(game, winningTeam, points),
  );
}

function dealHand(game: GameState): void {
  game.dealerIndex = (game.dealerIndex + 1) % 6;
  game.phase = "playing";
  game.pendingChallenge = null;
  game.challengeNotice = null;
  game.challengeNoticeAccepted = false;
  game.challengeNoticeUntil = null;
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
  game.hiddenCards = Array.from({ length: 6 }, () => [] as string[]);
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
  setStatus(
    game,
    tenHand ? "Mão de dez: sem desafios, valendo 4." : "Nova disputa.",
  );
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

function isSignalEmojiPermutation(value: unknown): value is string[] {
  return (
    Array.isArray(value) &&
    value.length === signalEmojiPool.length &&
    new Set(value).size === signalEmojiPool.length &&
    signalEmojiPool.every((emoji) => value.includes(emoji))
  );
}

function isSignalEmojiMappings(value: unknown): value is string[][] {
  return (
    Array.isArray(value) &&
    value.length === 2 &&
    value.every(isSignalEmojiPermutation)
  );
}

export function normalizeSignalEmojisByTeam(value: unknown): string[][] {
  return isSignalEmojiMappings(value)
    ? value.map((emojis) => [...emojis])
    : [[...signalEmojiPool], [...signalEmojiPool]];
}

function shuffledSignalEmojis(): string[] {
  return shuffle([...signalEmojiPool]);
}

function shuffledSignalEmojisByTeam(): string[][] {
  return [shuffledSignalEmojis(), shuffledSignalEmojis()];
}

function hiddenPlaysForTeam(plays: PlayedCardState[], team: number): number {
  return plays.filter((play) => play.hidden && play.playerIndex % 2 === team)
    .length;
}

function nextChallengeAfter(currentValue: number): number | null {
  return (
    ({ 1: 2, 2: 3, 3: 4, 4: 6 } as Record<number, number>)[currentValue] ??
    null
  );
}

function spokenValueForPoints(points: number): number {
  return (
    ({ 2: 4, 3: 6, 4: 9, 6: 12 } as Record<number, number>)[points] ??
    points * 2
  );
}

function challengeLabelForPoints(points: number): string {
  return points === 2 ? "TRUCO!" : `VALE ${spokenValueForPoints(points)}!`;
}

function nextPlayerOnTeam(from: number, team: number): number {
  for (let offset = 1; offset < 6; offset += 1) {
    const candidate = (from + offset) % 6;
    if (candidate % 2 === team) return candidate;
  }
  return 0;
}

function hasLegalHiddenDiscards(
  plays: unknown[],
  scores: number[] | undefined,
): boolean {
  const typedPlays = plays.filter(
    (play): play is PlayedCardState =>
      typeof play === "object" &&
      play !== null &&
      Number.isInteger((play as PlayedCardState).playerIndex) &&
      (play as PlayedCardState).playerIndex >= 0 &&
      (play as PlayedCardState).playerIndex < 6 &&
      typeof (play as PlayedCardState).card === "string" &&
      ((play as PlayedCardState).hidden === undefined ||
        typeof (play as PlayedCardState).hidden === "boolean"),
  );
  const hiddenCount = typedPlays.filter((play) => play.hidden).length;
  return (
    typedPlays.length === plays.length &&
    (!scores?.includes(10) || hiddenCount === 0) &&
    hiddenPlaysForTeam(typedPlays, 0) <= 2 &&
    hiddenPlaysForTeam(typedPlays, 1) <= 2
  );
}

function setStatus(game: GameState, message: string): void {
  game.statusMessage = message;
  game.history.unshift(message);
  if (game.history.length > 30) game.history.length = 30;
}

function teamAction(
  game: GameState,
  team: number,
  ours: string,
  theirs: string,
): string {
  return team === (game.perspectiveTeam ?? 0)
    ? `Nós ${ours}`
    : `Eles ${theirs}`;
}

function teamWon(game: GameState, team: number, complement: string): string {
  return `${teamAction(game, team, "vencemos", "venceram")} ${complement}`;
}

function teamScored(game: GameState, team: number, points: number): string {
  return `${teamAction(game, team, "marcamos", "marcaram")} ${points} pontos.`;
}
