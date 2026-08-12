export type LobbyTablePhase = "empty" | "waiting" | "playing";

export interface LobbyTableStatus {
  tableNumber: number;
  status: LobbyTablePhase;
  playerCount: number;
  humanCount: number;
  botCount: number;
  capacity: number;
  seats: Array<Record<string, unknown> | null>;
  waitingStartAt: number | null;
}

export function isLobbyTableStatus(value: unknown): value is LobbyTableStatus {
  if (typeof value !== "object" || value === null) return false;
  const status = value as Partial<LobbyTableStatus>;
  return (
    Number.isInteger(status.tableNumber) &&
    status.tableNumber! >= 1 &&
    status.tableNumber! <= 10 &&
    (status.status === "empty" ||
      status.status === "waiting" ||
      status.status === "playing") &&
    typeof status.playerCount === "number" &&
    typeof status.humanCount === "number" &&
    typeof status.botCount === "number" &&
    status.capacity === 6 &&
    Array.isArray(status.seats) &&
    status.seats.length === 6 &&
    (status.waitingStartAt === null || typeof status.waitingStartAt === "number")
  );
}
