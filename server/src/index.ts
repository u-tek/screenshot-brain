// The Screenshot Brain account endpoint (Cloudflare Worker).
//
//   POST /token   {"code": "..."}            -> {"refresh_token": "..."}
//   POST /revoke  {"refresh_token": "..."}   -> 204
//
// Apple requires apps with Sign in with Apple to revoke the user's token when they delete their
// account. That needs the app's private key, which must never ship in the app, so it lives here
// as a secret. Nothing is stored: the refresh token goes back to the app's Keychain.

import { type AppleConfig, exchangeCode, revokeToken } from "./apple.ts";

export interface Env {
  APPLE_TEAM_ID: string;
  APPLE_KEY_ID: string;
  APPLE_CLIENT_ID: string;
  APPLE_PRIVATE_KEY: string;
}

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

export async function handle(request: Request, env: Env, fetcher: typeof fetch = fetch): Promise<Response> {
  const url = new URL(request.url);
  if (request.method !== "POST") return json({ error: "POST only" }, 405);

  let body: Record<string, unknown>;
  try {
    body = (await request.json()) as Record<string, unknown>;
  } catch {
    return json({ error: "Expected a JSON body" }, 400);
  }

  const config: AppleConfig = {
    teamID: env.APPLE_TEAM_ID,
    keyID: env.APPLE_KEY_ID,
    clientID: env.APPLE_CLIENT_ID,
    privateKey: env.APPLE_PRIVATE_KEY,
  };

  try {
    switch (url.pathname) {
      case "/token": {
        if (typeof body.code !== "string" || body.code.length === 0) return json({ error: "Missing code" }, 400);
        return json({ refresh_token: await exchangeCode(config, body.code, fetcher) });
      }
      case "/revoke": {
        const token = body.refresh_token;
        if (typeof token !== "string" || token.length === 0) return json({ error: "Missing refresh_token" }, 400);
        await revokeToken(config, token, fetcher);
        return new Response(null, { status: 204 });
      }
      default:
        return json({ error: "Not found" }, 404);
    }
  } catch (error) {
    // Never echo Apple's response or the token back: just say it failed.
    console.error(error instanceof Error ? error.message : error);
    return json({ error: "Apple didn't accept that" }, 502);
  }
}

export default {
  fetch: (request: Request, env: Env) => handle(request, env),
};
