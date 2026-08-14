export type ChallengeVoteChoice = "accept" | "fold" | "raise";
export type ChallengeVoteDecision = ChallengeVoteChoice | "pending";

export const challengeVoteTimeoutMs = 15_000;

export interface ChallengeVote {
  id: string;
  targetTeam: number;
  requestedValue: number;
  challengerPlayer: number;
  expiresAt: number;
  participantSeatIndexes: number[];
  votes: Array<ChallengeVoteChoice | null>;
}

export function createChallengeVote(
  id: string,
  targetTeam: number,
  requestedValue: number,
  challengerPlayer: number,
  participantSeatIndexes: number[],
  now: number,
  seatCount: number,
): ChallengeVote {
  return {
    id,
    targetTeam,
    requestedValue,
    challengerPlayer,
    expiresAt: now + challengeVoteTimeoutMs,
    participantSeatIndexes: [...participantSeatIndexes],
    votes: Array<ChallengeVoteChoice | null>(seatCount).fill(null),
  };
}

export function recordChallengeVote(
  vote: ChallengeVote,
  seatIndex: number,
  choice: ChallengeVoteChoice,
): boolean {
  if (
    !vote.participantSeatIndexes.includes(seatIndex) ||
    vote.votes[seatIndex] !== null
  ) {
    return false;
  }
  vote.votes[seatIndex] = choice;
  return true;
}

export function challengeVoteDecision(
  vote: ChallengeVote,
  now: number,
): ChallengeVoteDecision {
  if (vote.votes.some((choice) => choice === "raise")) return "raise";
  if (vote.votes.some((choice) => choice === "accept")) return "accept";
  if (
    vote.participantSeatIndexes.length > 0 &&
    vote.participantSeatIndexes.every(
      (seatIndex) => vote.votes[seatIndex] === "fold",
    )
  ) {
    return "fold";
  }
  if (now >= vote.expiresAt) return "fold";
  return "pending";
}

export function removeChallengeVoteParticipant(
  vote: ChallengeVote,
  seatIndex: number,
): boolean {
  const position = vote.participantSeatIndexes.indexOf(seatIndex);
  if (position < 0) return false;
  vote.participantSeatIndexes.splice(position, 1);
  vote.votes[seatIndex] = null;
  return true;
}
