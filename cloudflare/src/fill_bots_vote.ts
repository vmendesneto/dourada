export interface FillBotsVote {
  id: string;
  requesterSeatIndex: number;
  participantSeatIndexes: number[];
  votes: Array<boolean | null>;
  shownAt: Array<number | null>;
  expiresAt: number | null;
}

export type FillBotsVoteDecision = "pending" | "approved" | "rejected";

export const fillBotsVoteTimeoutMs = 10_000;

export function createFillBotsVote(
  id: string,
  requesterSeatIndex: number,
  participantSeatIndexes: number[],
  now: number,
  seatCount: number,
): FillBotsVote {
  const votes = Array<boolean | null>(seatCount).fill(null);
  const shownAt = Array<number | null>(seatCount).fill(null);
  votes[requesterSeatIndex] = true;
  shownAt[requesterSeatIndex] = now;
  return {
    id,
    requesterSeatIndex,
    participantSeatIndexes: [...participantSeatIndexes],
    votes,
    shownAt,
    expiresAt: null,
  };
}

export function recordFillBotsVoteShown(
  vote: FillBotsVote,
  seatIndex: number,
  now: number,
): boolean {
  if (
    seatIndex === vote.requesterSeatIndex ||
    !vote.participantSeatIndexes.includes(seatIndex) ||
    vote.shownAt[seatIndex] !== null
  ) {
    return false;
  }
  vote.shownAt[seatIndex] = now;
  const allDialogsShown = vote.participantSeatIndexes.every(
    (index) => vote.shownAt[index] !== null,
  );
  if (allDialogsShown) {
    const lastShownAt = Math.max(
      ...vote.participantSeatIndexes.map((index) => vote.shownAt[index] ?? now),
    );
    vote.expiresAt = lastShownAt + fillBotsVoteTimeoutMs;
  }
  return true;
}

export function recordFillBotsVote(
  vote: FillBotsVote,
  seatIndex: number,
  accepted: boolean,
): boolean {
  if (
    seatIndex === vote.requesterSeatIndex ||
    !vote.participantSeatIndexes.includes(seatIndex) ||
    vote.expiresAt === null ||
    vote.shownAt[seatIndex] === null ||
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
  if (vote.expiresAt !== null && now >= vote.expiresAt) return "rejected";
  if (vote.participantSeatIndexes.every((index) => vote.votes[index] === true)) {
    return "approved";
  }
  return "pending";
}
