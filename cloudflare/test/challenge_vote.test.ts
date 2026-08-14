import { describe, expect, it } from "vitest";
import {
  challengeVoteDecision,
  challengeVoteTimeoutMs,
  createChallengeVote,
  recordChallengeVote,
  removeChallengeVoteParticipant,
} from "../src/challenge_vote";

describe("decisao conjunta do trio para truco e aumentos", () => {
  const now = 1_000_000;

  it("aceita assim que qualquer humano aceita", () => {
    const vote = createChallengeVote("vote-1", 0, 2, 1, [0, 2, 4], now, 6);

    expect(recordChallengeVote(vote, 2, "accept")).toBe(true);
    expect(challengeVoteDecision(vote, now)).toBe("accept");
  });

  it("so corre quando todos os humanos correm", () => {
    const vote = createChallengeVote("vote-2", 0, 3, 1, [0, 2, 4], now, 6);

    expect(recordChallengeVote(vote, 0, "fold")).toBe(true);
    expect(recordChallengeVote(vote, 2, "fold")).toBe(true);
    expect(challengeVoteDecision(vote, now)).toBe("pending");
    expect(recordChallengeVote(vote, 4, "fold")).toBe(true);
    expect(challengeVoteDecision(vote, now)).toBe("fold");
  });

  it("aumenta assim que qualquer humano aumenta", () => {
    const vote = createChallengeVote("vote-3", 1, 4, 0, [1, 3, 5], now, 6);

    expect(recordChallengeVote(vote, 5, "raise")).toBe(true);
    expect(challengeVoteDecision(vote, now)).toBe("raise");
  });

  it("ignora segundo voto e jogador de outro trio", () => {
    const vote = createChallengeVote("vote-4", 0, 2, 1, [0, 2], now, 6);

    expect(recordChallengeVote(vote, 1, "accept")).toBe(false);
    expect(recordChallengeVote(vote, 0, "fold")).toBe(true);
    expect(recordChallengeVote(vote, 0, "accept")).toBe(false);
    expect(challengeVoteDecision(vote, now)).toBe("pending");
  });

  it("deixa de aguardar um humano que saiu da mesa", () => {
    const vote = createChallengeVote("vote-5", 0, 2, 1, [0, 2], now, 6);
    recordChallengeVote(vote, 0, "fold");

    expect(removeChallengeVoteParticipant(vote, 2)).toBe(true);
    expect(challengeVoteDecision(vote, now)).toBe("fold");
  });

  it("corre ao fim de 15 segundos quando ninguem aceita ou aumenta", () => {
    const vote = createChallengeVote("vote-6", 0, 2, 1, [0, 2], now, 6);

    expect(vote.expiresAt).toBe(now + challengeVoteTimeoutMs);
    expect(challengeVoteDecision(vote, vote.expiresAt - 1)).toBe("pending");
    expect(challengeVoteDecision(vote, vote.expiresAt)).toBe("fold");
  });

  it("tambem corre no prazo quando apenas parte do trio correu", () => {
    const vote = createChallengeVote("vote-7", 0, 2, 1, [0, 2], now, 6);
    recordChallengeVote(vote, 0, "fold");

    expect(challengeVoteDecision(vote, vote.expiresAt - 1)).toBe("pending");
    expect(challengeVoteDecision(vote, vote.expiresAt)).toBe("fold");
  });
});
