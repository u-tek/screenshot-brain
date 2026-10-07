// Sign in with Apple, server side: the client secret, the token exchange and revocation.
// No dependencies: Web Crypto signs the client secret (ES256), which Workers and Node both have.

export interface AppleConfig {
  teamID: string;
  keyID: string;
  /** The app's bundle ID: Sign in with Apple's client ID for a native app. */
  clientID: string;
  /** The contents of the .p8 key file from the developer portal. */
  privateKey: string;
}

const APPLE = "https://appleid.apple.com";

function base64url(data: ArrayBuffer | Uint8Array | string): string {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : new Uint8Array(data);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToPKCS8(pem: string): ArrayBuffer {
  const body = pem.replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "").replace(/\s+/g, "");
  const binary = atob(body);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

/** The short-lived JWT Apple accepts as a client secret. */
export async function clientSecret(config: AppleConfig, now = Math.floor(Date.now() / 1000)): Promise<string> {
  const header = { alg: "ES256", kid: config.keyID, typ: "JWT" };
  const payload = { iss: config.teamID, iat: now, exp: now + 300, aud: APPLE, sub: config.clientID };
  const signingInput = `${base64url(JSON.stringify(header))}.${base64url(JSON.stringify(payload))}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToPKCS8(config.privateKey),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  // Web Crypto returns the raw r||s signature JWS wants.
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(signingInput));
  return `${signingInput}.${base64url(signature)}`;
}

/** Swaps the app's one-time authorisation code for a refresh token. */
export async function exchangeCode(config: AppleConfig, code: string, fetcher: typeof fetch = fetch): Promise<string> {
  const response = await fetcher(`${APPLE}/auth/token`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: config.clientID,
      client_secret: await clientSecret(config),
      code,
      grant_type: "authorization_code",
    }),
  });
  if (!response.ok) throw new Error(`Apple token endpoint said ${response.status}`);
  const json = (await response.json()) as { refresh_token?: string };
  if (!json.refresh_token) throw new Error("Apple sent no refresh token");
  return json.refresh_token;
}

/** Revokes a refresh token: what account deletion requires. */
export async function revokeToken(config: AppleConfig, refreshToken: string, fetcher: typeof fetch = fetch): Promise<void> {
  const response = await fetcher(`${APPLE}/auth/revoke`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: config.clientID,
      client_secret: await clientSecret(config),
      token: refreshToken,
      token_type_hint: "refresh_token",
    }),
  });
  if (!response.ok) throw new Error(`Apple revoke endpoint said ${response.status}`);
}
