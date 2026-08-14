import { describe, expect, it } from "vitest";
import {
  createFillBotsVote,
  fillBotsVoteDecision,
  recordFillBotsVote,
  recordFillBotsVoteShown,
} from "../src/fill_bots_vote";

describe("votacao para completar a mesa com robos", () => {
  it("inicia os dez segundos somente depois que todos viram o dialogo", () => {
    const vote = createFillBotsVote("vote-1", 0, [0, 2, 4], 1_000, 6);

    expect(vote.expiresAt).toBeNull();
    expect(fillBotsVoteDecision(vote, 50_000)).toBe("pending");
    expect(recordFillBotsVoteShown(vote, 2, 5_000)).toBe(true);
    expect(vote.expiresAt).toBeNull();
    expect(recordFillBotsVoteShown(vote, 4, 7_000)).toBe(true);
    expect(vote.expiresAt).toBe(17_000);
  });

  it("aprova apenas quando todos os outros humanos aceitam", () => {
    const vote = createFillBotsVote("vote-2", 0, [0, 2, 4], 1_000, 6);
    recordFillBotsVoteShown(vote, 2, 2_000);
    recordFillBotsVoteShown(vote, 4, 3_000);

    expect(recordFillBotsVote(vote, 2, true)).toBe(true);
    expect(fillBotsVoteDecision(vote, 3_001)).toBe("pending");
    expect(recordFillBotsVote(vote, 4, true)).toBe(true);
    expect(fillBotsVoteDecision(vote, 3_001)).toBe("approved");
  });

  it("recusa imediatamente ao receber um nao", () => {
    const vote = createFillBotsVote("vote-3", 1, [1, 3, 5], 2_000, 6);
    recordFillBotsVoteShown(vote, 3, 3_000);
    recordFillBotsVoteShown(vote, 5, 3_000);

    expect(recordFillBotsVote(vote, 3, false)).toBe(true);
    expect(fillBotsVoteDecision(vote, 3_001)).toBe("rejected");
  });

  it("considera falta de resposta como nao dez segundos apos a exibicao", () => {
    const vote = createFillBotsVote("vote-4", 0, [0, 1], 5_000, 6);
    recordFillBotsVoteShown(vote, 1, 8_000);

    expect(fillBotsVoteDecision(vote, 17_999)).toBe("pending");
    expect(fillBotsVoteDecision(vote, 18_000)).toBe("rejected");
  });

  it("nao aceita voto antes da confirmacao de exibicao", () => {
    const vote = createFillBotsVote("vote-5", 0, [0, 2], 3_000, 6);

    expect(recordFillBotsVote(vote, 2, true)).toBe(false);
    expect(recordFillBotsVoteShown(vote, 2, 4_000)).toBe(true);
    expect(recordFillBotsVote(vote, 2, true)).toBe(true);
  });

  it("ignora confirmacao ou voto duplicado e jogadores de fora", () => {
    const vote = createFillBotsVote("vote-6", 0, [0, 2], 3_000, 6);

    expect(recordFillBotsVoteShown(vote, 0, 4_000)).toBe(false);
    expect(recordFillBotsVoteShown(vote, 1, 4_000)).toBe(false);
    expect(recordFillBotsVoteShown(vote, 2, 4_000)).toBe(true);
    expect(recordFillBotsVoteShown(vote, 2, 4_001)).toBe(false);
    expect(recordFillBotsVote(vote, 2, true)).toBe(true);
    expect(recordFillBotsVote(vote, 2, false)).toBe(false);
  });

  it("aprova imediatamente quando nao ha outro humano", () => {
    const vote = createFillBotsVote("vote-7", 0, [0], 1_000, 6);
    expect(fillBotsVoteDecision(vote, 1_000)).toBe("approved");
  });
});
