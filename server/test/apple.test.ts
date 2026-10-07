import assert from "node:assert/strict";
import { test } from "node:test";
import { clientSecret } from "../src/apple.ts";
import { handle } from "../src/index.ts";

async function makeKey() {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const pkcs8 = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...pkcs8))}\n-----END PRIVATE KEY-----`;
  return { pem, publicKey: pair.publicKey };
}

const fromBase64url = (text: string) => Uint8Array.from(atob(text.replace(/-/g, "+").replace(/_/g, "/")), (c) => c.charCodeAt(0));

test("the client secret is an ES256 JWT Apple can verify", async () => {
  const { pem, publicKey } = await makeKey();
  const jwt = await clientSecret({ teamID: "TEAM123456", keyID: "KEY1234567", clientID: "com.example.app", privateKey: pem }, 1_700_000_000);
  const [header, payload, signature] = jwt.split(".");
  assert.deepEqual(JSON.parse(new TextDecoder().decode(fromBase64url(header))), { alg: "ES256", kid: "KEY1234567", typ: "JWT" });
  const claims = JSON.parse(new TextDecoder().decode(fromBase64url(payload)));
  assert.equal(claims.iss, "TEAM123456");
  assert.equal(claims.sub, "com.example.app");
  assert.equal(claims.aud, "https://appleid.apple.com");
  assert.ok(claims.exp > claims.iat);
  const valid = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    publicKey,
    fromBase64url(signature),
    new TextEncoder().encode(`${header}.${payload}`),
  );
  assert.ok(valid);
});

test("token and revoke talk to Apple and never echo secrets", async () => {
  const { pem } = await makeKey();
  const env = { APPLE_TEAM_ID: "T", APPLE_KEY_ID: "K", APPLE_CLIENT_ID: "com.example.app", APPLE_PRIVATE_KEY: pem };
  const calls: string[] = [];
  const fakeApple = (async (url: string | URL | Request, init?: RequestInit) => {
    calls.push(String(url));
    const form = new URLSearchParams(String(init?.body));
    assert.equal(form.get("client_id"), "com.example.app");
    if (String(url).endsWith("/auth/token")) {
      assert.equal(form.get("code"), "abc");
      return new Response(JSON.stringify({ refresh_token: "r1" }), { status: 200 });
    }
    assert.equal(form.get("token"), "r1");
    return new Response(null, { status: 200 });
  }) as typeof fetch;

  const post = (path: string, body: unknown) =>
    new Request(`https://worker.example${path}`, { method: "POST", body: JSON.stringify(body) });

  const token = await handle(post("/token", { code: "abc" }), env, fakeApple);
  assert.deepEqual(await token.json(), { refresh_token: "r1" });
  const revoke = await handle(post("/revoke", { refresh_token: "r1" }), env, fakeApple);
  assert.equal(revoke.status, 204);
  assert.deepEqual(calls, ["https://appleid.apple.com/auth/token", "https://appleid.apple.com/auth/revoke"]);

  const failing = (async () => new Response("{\"error\":\"invalid_grant\"}", { status: 400 })) as typeof fetch;
  const failed = await handle(post("/token", { code: "bad" }), env, failing);
  assert.equal(failed.status, 502);
  assert.deepEqual(await failed.json(), { error: "Apple didn't accept that" });

  assert.equal((await handle(post("/token", {}), env, fakeApple)).status, 400);
  assert.equal((await handle(new Request("https://worker.example/token"), env, fakeApple)).status, 405);
});
