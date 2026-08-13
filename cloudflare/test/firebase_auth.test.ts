import { describe, expect, it, vi } from "vitest";
import { verifyFirebaseIdToken } from "../src/firebase_auth";

describe("autenticação Firebase", () => {
  it("aceita um token confirmado pelo projeto game-real-time", async () => {
    const fetcher = vi.fn(async () =>
      Response.json({
        users: [
          {
            localId: "firebase-user-1",
            email: "jogador@exemplo.com",
            displayName: "Jogador",
            photoUrl: "https://example.com/avatar.jpg",
          },
        ],
      }),
    );

    await expect(
      verifyFirebaseIdToken("token-firebase-valido-com-tamanho", fetcher),
    ).resolves.toEqual({
      uid: "firebase-user-1",
      email: "jogador@exemplo.com",
      displayName: "Jogador",
      photoUrl: "https://example.com/avatar.jpg",
    });
    expect(fetcher).toHaveBeenCalledOnce();
  });

  it("recusa token ausente ou rejeitado pelo Firebase", async () => {
    const fetcher = vi.fn(async () => Response.json({}, { status: 400 }));

    await expect(verifyFirebaseIdToken(null, fetcher)).resolves.toBeNull();
    await expect(
      verifyFirebaseIdToken("token-firebase-invalido-com-tamanho", fetcher),
    ).resolves.toBeNull();
  });
});
