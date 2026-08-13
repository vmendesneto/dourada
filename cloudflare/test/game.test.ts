import { describe, expect, it } from "vitest";
import {
  advanceBot,
  cardStrength,
  createInitialGame,
  resolveDisputeWinner,
  resolveTrickWinner,
  scorePoints,
  type GameState,
} from "../src/game";

const fixture = (): GameState => ({
  version: 1,
  scores: [0, 0],
  playerHands: [["3o"], ["4o"], ["5o"], ["6o"], ["7e"], ["Qo"]],
  currentTrick: [],
  playedCards: [],
  trickWinners: [],
  history: [],
  tenDecisionMade: [true, true],
  botChallengeConsideredThisTrick: [false, false],
  automaticTimeouts: [0, 0, 0, 0, 0, 0],
  dealerIndex: 5,
  trickLeaderIndex: 0,
  currentPlayerIndex: 0,
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
});

describe("motor do robô substituto", () => {
  it("permite que qualquer cadeira sorteada abra a primeira mão", () => {
    for (let firstPlayerIndex = 0; firstPlayerIndex < 6; firstPlayerIndex += 1) {
      const game = createInitialGame(firstPlayerIndex);

      expect(game.currentPlayerIndex).toBe(firstPlayerIndex);
      expect(game.trickLeaderIndex).toBe(firstPlayerIndex);
      expect(game.dealerIndex).toBe((firstPlayerIndex + 5) % 6);
    }
  });

  it("usa a mesma hierarquia e pontuação do Flutter", () => {
    expect(cardStrength("Qo")).toBe(19);
    expect(cardStrength("7o")).toBe(11);
    expect(cardStrength("3c")).toBe(10);
    expect(scorePoints(1)).toBe(2);
    expect(scorePoints(4)).toBe(8);
    expect(scorePoints(6)).toBe(12);
  });

  it("mantém as regras de empate das três mãos", () => {
    expect(resolveDisputeWinner([0, null])).toBe(0);
    expect(resolveDisputeWinner([null, 1])).toBe(1);
    expect(resolveDisputeWinner([0, 1, null])).toBe(0);
    expect(resolveDisputeWinner([null, null, null])).toBeNull();
  });

  it("resolve empate somente quando as maiores cartas são de trios diferentes", () => {
    expect(
      resolveTrickWinner([
        { playerIndex: 0, card: "3o" },
        { playerIndex: 1, card: "3c" },
      ]),
    ).toBeNull();
    expect(
      resolveTrickWinner([
        { playerIndex: 0, card: "3o" },
        { playerIndex: 2, card: "3c" },
        { playerIndex: 1, card: "2o" },
      ]),
    ).toBe(0);
  });

  it("joga automaticamente pela cadeira humana ausente", () => {
    const step = advanceBot(fixture());
    expect(step.state.playerHands[0]).toHaveLength(0);
    expect(step.state.playedCards).toEqual([{ playerIndex: 0, card: "3o" }]);
    expect(step.state.currentPlayerIndex).toBe(1);
    expect(step.nextDelayMs).toBe(650);
  });

  it("mantém Nós relativo à equipe do usuário", () => {
    const ours = fixture();
    ours.phase = "handFinished";
    ours.matchWinner = 1;
    ours.perspectiveTeam = 1;

    const theirs = structuredClone(ours);
    theirs.perspectiveTeam = 0;

    expect(advanceBot(ours).state.statusMessage).toBe(
      "Nós vencemos a partida!",
    );
    expect(advanceBot(theirs).state.statusMessage).toBe(
      "Eles venceram a partida!",
    );
  });
});
