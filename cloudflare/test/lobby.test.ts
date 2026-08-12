import { describe, expect, it } from "vitest";
import { isLobbyTableStatus } from "../src/lobby";

const validStatus = () => ({
  tableNumber: 1,
  status: "waiting",
  playerCount: 1,
  humanCount: 1,
  botCount: 0,
  capacity: 6,
  seats: [{ index: 0, kind: "human", connected: true }, null, null, null, null, null],
  waitingStartAt: null,
});

describe("atualizações do lobby", () => {
  it("aceita somente estados das dez mesas fixas", () => {
    expect(isLobbyTableStatus(validStatus())).toBe(true);
    expect(isLobbyTableStatus({ ...validStatus(), tableNumber: 11 })).toBe(false);
    expect(isLobbyTableStatus({ ...validStatus(), seats: [] })).toBe(false);
  });
});
