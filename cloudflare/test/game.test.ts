import { describe, expect, it } from "vitest";
import {
  acceptPendingChallenge,
  advanceBot,
  betweenPartidasTransitionMs,
  cardStrength,
  createInitialGame,
  foldPendingChallenge,
  handTransitionMs,
  isGameState,
  raisePendingChallenge,
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
    for (
      let firstPlayerIndex = 0;
      firstPlayerIndex < 6;
      firstPlayerIndex += 1
    ) {
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

  it("desconsidera cartas escondidas ao resolver a mão", () => {
    expect(
      resolveTrickWinner([
        { playerIndex: 0, card: "Qo", hidden: true },
        { playerIndex: 1, card: "4o" },
      ]),
    ).toBe(1);
    expect(
      resolveTrickWinner([
        { playerIndex: 0, card: "Qo", hidden: true },
        { playerIndex: 1, card: "3o", hidden: true },
      ]),
    ).toBeNull();
  });

  it("rejeita três descartes escondidos do mesmo trio e qualquer um na mão de dez", () => {
    const threeHidden = fixture();
    threeHidden.currentTrick = [
      { playerIndex: 0, card: "4o", hidden: true },
      { playerIndex: 2, card: "5o", hidden: true },
      { playerIndex: 4, card: "6o", hidden: true },
    ];
    expect(isGameState(threeHidden)).toBe(false);

    const tenHand = fixture();
    tenHand.scores[0] = 10;
    tenHand.currentTrick = [{ playerIndex: 1, card: "4o", hidden: true }];
    expect(isGameState(tenHand)).toBe(false);
  });

  it("rejeita desafio com trio, valor ou jogador inválido", () => {
    const game = fixture();
    game.pendingChallenge = {
      challengerTeam: 0,
      challengerPlayer: 7,
      targetTeam: 0,
      requestedValue: 5,
      responderPlayer: -1,
    };

    expect(isGameState(game)).toBe(false);
  });

  it("joga automaticamente pela cadeira humana ausente", () => {
    const step = advanceBot(fixture());
    expect(step.state.playerHands[0]).toHaveLength(0);
    expect(step.state.playedCards).toEqual([{ playerIndex: 0, card: "3o" }]);
    expect(step.state.currentPlayerIndex).toBe(1);
    expect(step.nextDelayMs).toBe(650);
  });

  it("aguarda dois segundos depois de concluir uma mão", () => {
    const game = fixture();
    game.playerHands = [[], [], [], [], [], ["4p"]];
    game.currentTrick = [
      { playerIndex: 0, card: "Qo" },
      { playerIndex: 1, card: "4o" },
      { playerIndex: 2, card: "5o" },
      { playerIndex: 3, card: "6o" },
      { playerIndex: 4, card: "7e" },
    ];
    game.playedCards = [...game.currentTrick];
    game.currentPlayerIndex = 5;

    const step = advanceBot(game);

    expect(step.state.awaitingNextTrick).toBe(true);
    expect(step.nextDelayMs).toBe(handTransitionMs);
    expect(handTransitionMs).toBe(2000);
  });

  it("aguarda três segundos e meio entre partidas da mesma queda", () => {
    const game = fixture();
    game.trickWinners = [0];
    game.playerHands = [[], [], [], [], [], ["4p"]];
    game.currentTrick = [
      { playerIndex: 0, card: "Qo" },
      { playerIndex: 1, card: "4o" },
      { playerIndex: 2, card: "5o" },
      { playerIndex: 3, card: "6o" },
      { playerIndex: 4, card: "7e" },
    ];
    game.playedCards = [...game.currentTrick];
    game.currentPlayerIndex = 5;

    const step = advanceBot(game);

    expect(step.state.phase).toBe("handFinished");
    expect(step.state.matchWinner).toBeNull();
    expect(step.nextDelayMs).toBe(betweenPartidasTransitionMs);
    expect(betweenPartidasTransitionMs).toBe(3500);
  });

  it("não soma a pausa de nova partida quando a queda terminou", () => {
    const game = fixture();
    game.scores[0] = 10;
    game.trickWinners = [0];
    game.playerHands = [[], [], [], [], [], ["4p"]];
    game.currentTrick = [
      { playerIndex: 0, card: "Qo" },
      { playerIndex: 1, card: "4o" },
      { playerIndex: 2, card: "5o" },
      { playerIndex: 3, card: "6o" },
      { playerIndex: 4, card: "7e" },
    ];
    game.playedCards = [...game.currentTrick];
    game.currentPlayerIndex = 5;

    const step = advanceBot(game);

    expect(step.state.matchWinner).toBe(0);
    expect(step.nextDelayMs).toBe(handTransitionMs);
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

  it("aplica no servidor aceitar, correr e aumentar", () => {
    const challenged = fixture();
    challenged.pendingChallenge = {
      challengerTeam: 1,
      challengerPlayer: 1,
      targetTeam: 0,
      requestedValue: 2,
      responderPlayer: 2,
    };

    const accepted = structuredClone(challenged);
    expect(acceptPendingChallenge(accepted)).toBe(true);
    expect(accepted.handValue).toBe(2);
    expect(accepted.pendingChallenge).toBeNull();
    expect(accepted.challengeNoticeAccepted).toBe(true);
    expect(accepted.challengeNotice).toContain("aceitamos o desafio");

    const folded = structuredClone(challenged);
    expect(foldPendingChallenge(folded)).toBe(true);
    expect(folded.phase).toBe("handFinished");
    expect(folded.scores).toEqual([0, 2]);
    expect(folded.statusMessage).toContain("corremos do desafio");
    expect(folded.challengeNoticeAccepted).toBe(false);
    expect(folded.challengeNotice).toContain("corremos do desafio");

    const raised = structuredClone(challenged);
    expect(raisePendingChallenge(raised, 4)).toBe(true);
    expect(raised.handValue).toBe(2);
    expect(raised.pendingChallenge).toEqual({
      challengerTeam: 0,
      challengerPlayer: 4,
      targetTeam: 1,
      requestedValue: 3,
      responderPlayer: 5,
    });
  });
});
