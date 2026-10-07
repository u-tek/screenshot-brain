# Account endpoint

A Cloudflare Worker with two routes. Apple requires apps that offer Sign in with Apple to revoke
the user's token when they delete their account, and that takes the app's Sign in with Apple
private key, which must never ship inside the app.

| Route | Body | Returns |
|---|---|---|
| `POST /token` | `{"code": "<authorization code>"}` | `{"refresh_token": "..."}` |
| `POST /revoke` | `{"refresh_token": "..."}` | `204` |

The app calls `/token` right after sign-in (the code is single-use and lasts five minutes) and keeps
the refresh token in the Keychain. Account deletion in Settings calls `/revoke`. The Worker stores
nothing and logs no tokens.

## Deploy

You need a Cloudflare account and, in the Apple developer portal, a key with Sign in with Apple
enabled (Certificates, Identifiers & Profiles → Keys). Download the `.p8` file once; Apple won't let
you download it again.

```sh
cd server
npm install
npx wrangler login
npx wrangler secret put APPLE_TEAM_ID       # e.g. ABCDE12345
npx wrangler secret put APPLE_KEY_ID        # the key's 10-character ID
npx wrangler secret put APPLE_CLIENT_ID     # the app's bundle ID
npx wrangler secret put APPLE_PRIVATE_KEY < AuthKey_XXXXXXXXXX.p8
npx wrangler deploy
```

Then put the Worker's host (no `https://`, because `//` starts a comment in xcconfig files) in
`Config/Local.xcconfig`:

```
SB_ACCOUNT_SERVER_HOST = screenshot-brain-account.yourname.workers.dev
```

## Test

```sh
npm test
```

The tests sign a client secret with a throwaway key and verify it, and run both routes against a
fake Apple.
