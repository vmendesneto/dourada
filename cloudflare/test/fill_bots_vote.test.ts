import { describe, expect, it } from "vitest";
import {
  createFillBotsVote,
  fillBotsVoteDecision,
  recordFillBotsVote,
} from "../src/fill_bots_vote";

describe("votacao para completar a mesa com robos", () => {
  it("aprova apenas quando todos os outros humanos aceitam", () => {
    const vote = createFillBotsVote(0, [0, 2, 4], 1_000, 6);
    expect(fillBotsVoteDecision(vote, 1_000)).toBe("pending");
    expect(recordFillBotsVote(vote, 2, true)).toBe(true);
    expect(fillBotsVoteDecision(vote, 1_000)).toBe("pending");
    expect(recordFillBotsVote(vote, 4, true)).toBe(true);
    expect(fillBotsVoteDecision(vote, 1_000)).toBe("approved");
  });

  it("recusa imediatamente ao receber um nao", () => {
    const vote = createFillBotsVote(1, [1, 3, 5], 2_000, 6);
    expect(recordFillBotsVote(vote, 3, false)).toBe(true);
    expect(fillBotsVoteDecision(vote, 2_001)).toBe("rejected");
  });

  it("considera falta de resposta como nao depois de dez segundos", () => {
    const vote = createFillBotsVote(0, [0, 1], 5_000, 6);
    expect(fillBotsVoteDecision(vote, 14_999)).toBe("pending");
    expect(fillBotsVoteDecision(vote, 15_000)).toBe("rejected");
  });

  it("não aceita um voto que só completa a unanimidade após o prazo", () => {
    const vote = createFillBotsVote(0, [0, 1], 5_000, 6);
    expect(recordFillBotsVote(vote, 1, true)).toBe(true);
    expect(fillBotsVoteDecision(vote, 15_000)).toBe("rejected");
  });

  it("ignora voto duplicado, do solicitante ou de quem entrou depois", () => {
    const vote = createFillBotsVote(0, [0, 2], 3_000, 6);
    expect(recordFillBotsVote(vote, 0, false)).toBe(false);
    expect(recordFillBotsVote(vote, 1, true)).toBe(false);
    expect(recordFillBotsVote(vote, 2, true)).toBe(true);
    expect(recordFillBotsVote(vote, 2, false)).toBe(false);
  });
});
