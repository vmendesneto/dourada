const firebaseApiKey = "AIzaSyA6MZRx-7p-A-RQ1My7SPiV9RCecAZnRaY";
const firebaseLookupUrl =
  `https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=${firebaseApiKey}`;

export interface FirebaseIdentity {
  uid: string;
  email: string | null;
  displayName: string | null;
}

type Fetcher = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;

export async function verifyFirebaseIdToken(
  idToken: unknown,
  fetcher: Fetcher = fetch,
): Promise<FirebaseIdentity | null> {
  if (typeof idToken !== "string" || idToken.length < 20 || idToken.length > 8192) {
    return null;
  }

  try {
    const response = await fetcher(firebaseLookupUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ idToken }),
      signal: AbortSignal.timeout(6000),
    });
    if (!response.ok) return null;

    const payload = (await response.json()) as {
      users?: Array<{
        localId?: unknown;
        email?: unknown;
        displayName?: unknown;
      }>;
    };
    const user = payload.users?.[0];
    if (!user || typeof user.localId !== "string" || user.localId.length === 0) {
      return null;
    }
    return {
      uid: user.localId,
      email: typeof user.email === "string" ? user.email : null,
      displayName: typeof user.displayName === "string" ? user.displayName : null,
    };
  } catch {
    return null;
  }
}
