export interface FillBotsVote {
  requesterSeatIndex: number;
  participantSeatIndexes: number[];
  votes: Array<boolean | null>;
  expiresAt: number;
}

export type FillBotsVoteDecision = "pending" | "approved" | "rejected";

export const fillBotsVoteTimeoutMs = 10_000;

export function createFillBotsVote(
  requesterSeatIndex: number,
  participantSeatIndexes: number[],
  now: number,
  seatCount: number,
): FillBotsVote {
  const votes = Array<boolean | null>(seatCount).fill(null);
  votes[requesterSeatIndex] = true;
  return {
    requesterSeatIndex,
    participantSeatIndexes: [...participantSeatIndexes],
    votes,
    expiresAt: now + fillBotsVoteTimeoutMs,
  };
}

export function recordFillBotsVote(
  vote: FillBotsVote,
  seatIndex: number,
  accepted: boolean,
): boolean {
  if (
    seatIndex === vote.requesterSeatIndex ||
    !vote.participantSeatIndexes.includes(seatIndex) ||
    vote.votes[seatIndex] !== null
  ) {
    return false;
  }
  vote.votes[seatIndex] = accepted;
  return true;
}

export function fillBotsVoteDecision(
  vote: FillBotsVote,
  now: number,
): FillBotsVoteDecision {
  if (vote.participantSeatIndexes.some((index) => vote.votes[index] === false)) {
    return "rejected";
  }
  if (now >= vote.expiresAt) return "rejected";
  if (vote.participantSeatIndexes.every((index) => vote.votes[index] === true)) {
    return "approved";
  }
  return "pending";
}
