---
id: SPEC-007
topic: tidal-sonics
kind: spec
date: 2026-09-23
last_updated: 2026-09-23
status: Ready
depends_on:
  - SPEC-006
supersedes:
superseded_by:
adr: adr/ADR-007.md
reference: reference/SPEC-007.md
context_files:
  - src/TidalSonics.Server/Program.cs
  - src/TidalSonics.Server/appsettings.json
  - src/TidalSonics.Server/Tools/HelloTool.cs
success_criteria:
  - /.well-known/oauth-protected-resource` returns a valid RFC 9728 document; `resource` field matches the MCP URL the user enters in claude.ai
  - /.well-known/oauth-authorization-server` returns a valid RFC 8414 document advertising S256 PKCE
  - An unauthenticated POST to `/mcp` returns 401 with `WWW-Authenticate: Bearer ... resource_metadata="..."`
  - A curl-driven authorization-code+PKCE flow against `/authorize` and `/token` yields a valid JWT, which then succeeds against `/mcp`
  - claude.ai's "TIDAL Sonics" connector (re-added with OAuth client ID/secret in Advanced settings) successfully completes the full Google → AS → token → tool-call flow end-to-end
  - The `Hello` tool, when called from claude.ai, succeeds; when called from MCP Inspector against `/mcp` without a token, fails with 401
---

# SPEC-007: OAuth Authorization Server and JWT-protected MCP endpoint

## ADR

Decisions and rationale for this slice live in [`adr/ADR-007.md`](../adr/ADR-007.md). Read it before starting; do not restate it here.

## Specs

### Spec 1: Generate the RSA signing key

One-time setup. Generate a 2048-bit RSA key, store the PEM-encoded private key in user-secrets:

```bash
# Generate a key locally and copy it into user-secrets
openssl genrsa 2048 | tee /tmp/tidal-sonics-signing.pem
cd src/TidalSonics.Server
dotnet user-secrets set "OAuth:SigningKeyPem" "$(cat /tmp/tidal-sonics-signing.pem)"
rm /tmp/tidal-sonics-signing.pem
```

The key never leaves your machine in this slice; SPEC-010 migrates it to Key Vault. Treat the PEM like a password — anyone with it can mint tokens that your server will accept.

### Spec 2: Pre-registered client configuration

Set the claude.ai client credentials in user-secrets:

```bash
# Generate a random client secret
export CLIENT_SECRET=$(openssl rand -base64 32)
echo "Save this client secret — you'll paste it into claude.ai later:"
echo "$CLIENT_SECRET"

dotnet user-secrets set "OAuth:Clients:0:ClientId" "claude-ai-prod"
dotnet user-secrets set "OAuth:Clients:0:ClientSecret" "$CLIENT_SECRET"
dotnet user-secrets set "OAuth:Clients:0:RedirectUris:0" "https://claude.ai/api/mcp/auth_callback"
dotnet user-secrets set "OAuth:Clients:0:RedirectUris:1" "https://claude.com/api/mcp/auth_callback"
```

Add the shape to `appsettings.json` so the keys are discoverable:

> **Code lives in reference.** config (JSON) block 1 of `reference/SPEC-007.md` ("Spec 2: Pre-registered client configuration"). Write it yourself first; open the reference only if stuck.

### Spec 3: NuGet packages

```bash
cd src/TidalSonics.Server
dotnet add package Microsoft.AspNetCore.Authentication.JwtBearer
dotnet add package Microsoft.IdentityModel.Tokens
dotnet add package System.IdentityModel.Tokens.Jwt
```

The first is the JwtBearer authentication scheme. The second and third are the token construction and validation primitives Microsoft ships separately from the bearer handler.

### Spec 4: OAuth services

Three small services, all in a new `OAuth/` folder under the project:

**`OAuth/SigningKeyProvider.cs`** — loads the PEM into an `RsaSecurityKey` once at startup.

> **Code lives in reference.** C# block 2 of `reference/SPEC-007.md` ("Spec 4: OAuth services"). Write it yourself first; open the reference only if stuck.
> Shape: `class SigningKeyProvider`

**`OAuth/AuthorizationCodeStore.cs`** — in-memory short-lived code storage.

> **Code lives in reference.** C# block 3 of `reference/SPEC-007.md` ("Spec 4: OAuth services"). Write it yourself first; open the reference only if stuck.
> Shape: `record AuthorizationCode` · `class AuthorizationCodeStore` · `public void Add(…)` · `public AuthorizationCode? TakeIfValid(…)`

Take-once semantics (`TryRemove`) enforce one-use codes. Expiry check is defensive — codes that timeout are cleaned out on use.

**`OAuth/TokenIssuer.cs`** — mints JWTs for a given user + resource.

> **Code lives in reference.** C# block 4 of `reference/SPEC-007.md` ("Spec 4: OAuth services"). Write it yourself first; open the reference only if stuck.
> Shape: `class TokenIssuer`

Register all three as singletons in `Program.cs`:

> **Code lives in reference.** C# block 5 of `reference/SPEC-007.md` ("Spec 4: OAuth services"). Write it yourself first; open the reference only if stuck.

### Spec 5: Forwarded headers + issuer helper

Container Apps and dev tunnels both sit in front of the app; `Request.Scheme` and `Request.Host` only reflect the public URL if `ForwardedHeaders` middleware processes their `X-Forwarded-*` headers. Add this to `Program.cs` early in the pipeline:

> **Code lives in reference.** C# block 6 of `reference/SPEC-007.md` ("Spec 5: Forwarded headers + issuer helper"). Write it yourself first; open the reference only if stuck.

Clearing `KnownNetworks` and `KnownProxies` is what makes this work behind Container Apps and dev tunnels (which aren't local proxies). Acceptable trust posture for our deployment; revisit if you ever put your own reverse proxy in front.

Helper for computing the issuer URL from any request:

> **Code lives in reference.** C# block 7 of `reference/SPEC-007.md` ("Spec 5: Forwarded headers + issuer helper"). Write it yourself first; open the reference only if stuck.

### Spec 6: Protected Resource Metadata endpoint

> **Code lives in reference.** C# block 8 of `reference/SPEC-007.md` ("Spec 6: Protected Resource Metadata endpoint"). Write it yourself first; open the reference only if stuck.
> Shape: `GET /.well-known/oauth-protected-resource`

The `resource` value must match the URL the user types into claude.ai. We've consistently used `/mcp` since SPEC-001, so this aligns.

### Spec 7: Authorization Server Metadata endpoint

> **Code lives in reference.** C# block 9 of `reference/SPEC-007.md` ("Spec 7: Authorization Server Metadata endpoint"). Write it yourself first; open the reference only if stuck.
> Shape: `GET /.well-known/oauth-authorization-server`

S256 is the load-bearing line. claude.ai checks for it before initiating PKCE.

### Spec 8: `/authorize` endpoint

The flow: incoming request from claude.ai with `client_id`, `redirect_uri`, `response_type=code`, `code_challenge`, `code_challenge_method=S256`, `state`, `scope`, optional `resource`. We:

1. Validate `client_id` and `redirect_uri` against pre-registered list.
2. Check cookie auth. If not signed in, challenge through Google with a `returnUrl` of the same `/authorize` URL (query string preserved).
3. Generate an auth code, store it with the PKCE challenge and resource, redirect to `redirect_uri` with `code` and `state`.

> **Code lives in reference.** C# block 10 of `reference/SPEC-007.md` ("Spec 8: `/authorize` endpoint"). Write it yourself first; open the reference only if stuck.
> Shape: `GET /authorize`

`ClientConfig` lives at the bottom of `Program.cs` or in `OAuth/ClientConfig.cs` — wherever's tidier.

### Spec 9: `/token` endpoint

POST with `grant_type=authorization_code`, `code`, `redirect_uri`, `code_verifier`, plus client auth via HTTP Basic header (`Authorization: Basic base64(client_id:client_secret)`) or form fields. We:

1. Authenticate the client.
2. Look up and consume the auth code.
3. Verify the PKCE verifier hashes to the stored challenge.
4. Verify redirect URI matches the one bound to the code.
5. Mint and return the JWT.

> **Code lives in reference.** C# block 11 of `reference/SPEC-007.md` ("Spec 9: `/token` endpoint"). Write it yourself first; open the reference only if stuck.
> Shape: `POST /token`

### Spec 10: JWT Bearer on `/mcp`

Wire JWT validation into `Program.cs`. The trick is that the validation parameters depend on the dynamic issuer (which can be any of the three URLs we expose), so we use `IssuerValidator` to accept any HTTPS URL hosting our server rather than pinning to one issuer string. Acceptable here because the same key signs all tokens — they can't be replayed across servers.

In the `AddAuthentication` chain (extending what SPEC-006 set up), add JWT:

> **Code lives in reference.** C# block 12 of `reference/SPEC-007.md` ("Spec 10: JWT Bearer on `/mcp`"). Write it yourself first; open the reference only if stuck.

Then require auth on the MCP endpoint:

> **Code lives in reference.** C# block 13 of `reference/SPEC-007.md` ("Spec 10: JWT Bearer on `/mcp`"). Write it yourself first; open the reference only if stuck.
> Shape: `MapMcp()`

And on the McpServer builder, enable authorization filters so `[Authorize]` on tool methods works (it's automatically called by `WithHttpTransport()` in recent SDK versions, but explicit is clearer):

> **Code lives in reference.** C# block 14 of `reference/SPEC-007.md` ("Spec 10: JWT Bearer on `/mcp`"). Write it yourself first; open the reference only if stuck.

Decorate `Hello` with `[Authorize]`:

> **Code lives in reference.** C# block 15 of `reference/SPEC-007.md` ("Spec 10: JWT Bearer on `/mcp`"). Write it yourself first; open the reference only if stuck.
> Shape: `public static string Hello(…)`

### Spec 11: Default scheme handling

With cookie + Google + JWT all registered, the default scheme matters per route:

- `/signin`, `/signout`, `/me`, `/authorize`, `/access-denied`: **cookie** is the default (browser flow).
- `/mcp`: **JWT** explicitly via `RequireAuthorization(...)` (header bearer).

The defaults from SPEC-006 (`DefaultScheme = Cookies`, `DefaultChallengeScheme = Google`) stay correct for the browser endpoints. The MCP endpoint specifies its scheme explicitly, so default-scheme behavior doesn't apply there. No conflict.

### Spec 12: Reconfigure the claude.ai connector

Old "TIDAL Sonics" connector (prod, no auth) must be removed and re-added — claude.ai doesn't support editing in place:

1. claude.ai → **Customize** → **Connectors** → "TIDAL Sonics" → **Remove**.
2. **Add custom connector**:
   - Name: `TIDAL Sonics`
   - URL: `https://<app-fqdn>/mcp` (the SPEC-003 URL)
   - **Advanced settings:**
     - OAuth Client ID: `claude-ai-prod` (matches `OAuth:Clients:0:ClientId`)
     - OAuth Client Secret: the value generated in Spec 2 (saved aside earlier)
   - Click **Add**.

claude.ai now discovers your PRM, finds your AS, redirects you through `/authorize` → Google → back → `/token` → JWT. Subsequent tool calls send the JWT as `Authorization: Bearer`.

(Leave the dev connector pointing at the tunnel alone for now; we'll reconfigure it the same way after first verifying the curl flow and then prod, to avoid debugging two paths simultaneously.)

### Spec 13: Curl-based validation

Before involving claude.ai, drive the OAuth flow manually with curl + a browser. This separates "my AS is broken" from "claude.ai's flow doesn't like my AS."

```bash
export BASE=https://<app-fqdn>     # or your tunnel URL, or http://localhost:3001
export CLIENT_ID=claude-ai-prod
export CLIENT_SECRET=<the secret you generated in Spec 2>
export REDIRECT_URI=https://claude.ai/api/mcp/auth_callback
export STATE=$(openssl rand -hex 8)
export VERIFIER=$(openssl rand -base64 32 | tr -d '=+/' | head -c 64)
export CHALLENGE=$(echo -n "$VERIFIER" | openssl dgst -sha256 -binary | base64 | tr -d '=+/')
```

In a browser, navigate to:

```
${BASE}/authorize?response_type=code&client_id=${CLIENT_ID}&redirect_uri=${REDIRECT_URI}&state=${STATE}&scope=mcp:tools&code_challenge=${CHALLENGE}&code_challenge_method=S256&resource=${BASE}/mcp
```

(With variables substituted in your shell — `echo "${BASE}/authorize?..."` to get the full URL.)

You'll be bounced through Google, then redirected to `https://claude.ai/api/mcp/auth_callback?code=...&state=...`. The redirect will fail in the browser (claude.ai isn't expecting this), but copy the `code` value from the URL.

Exchange it for a token:

```bash
export CODE=<paste from URL>

curl -s -X POST ${BASE}/token \
  -u "${CLIENT_ID}:${CLIENT_SECRET}" \
  -d grant_type=authorization_code \
  -d code=${CODE} \
  -d redirect_uri=${REDIRECT_URI} \
  -d code_verifier=${VERIFIER} | jq .
```

Expect `{ "access_token": "...", "token_type": "Bearer", "expires_in": 86400, "scope": "mcp:tools" }`.

Call `/mcp` with the token:

```bash
export TOKEN=<paste access_token from previous>

curl -s -X POST ${BASE}/mcp \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${TOKEN}" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | jq .
```

Expect the `Hello` tool in the response. Then call `/mcp` again without the header to confirm 401 + `WWW-Authenticate` header pointing at `/.well-known/oauth-protected-resource`.

### Spec 14: End-to-end via claude.ai

After Spec 13 passes:

1. Reconfigure the claude.ai connector per Spec 12.
2. Start a new claude.ai conversation, enable **TIDAL Sonics**.
3. claude.ai will trigger the OAuth flow on first use — browser popup, Google sign-in (if cookie expired), redirect, success.
4. Ask Claude to call `Hello` with name "Jeremy". Confirm response.
5. Tail `az containerapp logs show --follow` during the flow; expect to see `/authorize`, `/token`, and `/mcp` traffic in sequence.

If all of Specs 13 and 14 pass, SPEC-007 is **Completed**.

## Tasks

### Task 1: Generate the signing key and configure secrets

Spec 1 and Spec 2 commands. Verify `dotnet user-secrets list` shows the key, the access-token lifetime, and the client config. **Save the generated `CLIENT_SECRET` somewhere you can find it** — you'll paste it into claude.ai later.

### Task 2: Add the OAuth shape to `appsettings.json`

Add the `OAuth` section from Spec 2. Commit: `chore: add OAuth config shape`.

### Task 3: NuGet packages

Run Spec 3 commands. Commit: `chore: add JwtBearer and IdentityModel packages`.

### Task 4: Implement the OAuth services

Create the three classes from Spec 4 in `src/TidalSonics.Server/OAuth/`. Register them in `Program.cs`. Build. Commit: `feat: add SigningKeyProvider, AuthorizationCodeStore, TokenIssuer`.

### Task 5: Add forwarded headers and the issuer helper

Apply Spec 5 changes to `Program.cs`. Commit: `feat: trust forwarded headers for dynamic issuer derivation`.

### Task 6: Add the two `.well-known` endpoints

Implement Specs 6 and 7. Hit them from a browser at all three URLs (local, tunnel, prod) and confirm the issuer values reflect the URL you used. Commit: `feat: add OAuth PRM and AS metadata endpoints`.

### Task 7: Implement `/authorize`

Spec 8. Test manually in a browser using a constructed URL (Spec 13's setup, but stop at the redirect to `claude.ai`). Confirm the redirect contains a `code` and `state` query parameter. Commit: `feat: add /authorize endpoint with PKCE and cookie-gated flow`.

### Task 8: Implement `/token`

Spec 9. Use Spec 13's curl commands to exchange the code from Task 7 for a JWT. Decode the JWT at https://jwt.io or with `dotnet run` to confirm claims look right (sub, email, iss, aud, exp). Commit: `feat: add /token endpoint with PKCE verification and JWT issuance`.

### Task 9: Protect `/mcp`

Spec 10 and Spec 11. Verify with curl: unauthenticated `/mcp` returns 401 with `WWW-Authenticate`; authenticated returns tools. Inspector against `/mcp` should fail (no token); update Inspector to use the JWT in its Authorization header to keep it working — Inspector has a "Token" field for this.

Commit: `feat: protect /mcp with JWT Bearer authentication`.

### Task 10: Reconfigure the claude.ai prod connector

Spec 12. Remove the old connector, add it back with the client credentials.

### Task 11: End-to-end test

Spec 14. New conversation, enable the connector, ask for `Hello`, confirm round-trip. Capture the conversation URL privately. Tail logs to confirm `/authorize`, `/token`, `/mcp` all hit.

### Task 12: Reconfigure the dev connector too

Same as Task 10 but pointing at the tunnel URL. Now both prod and dev are OAuth-gated and ready for tool development in subsequent specs.

If Tasks 11 and 12 pass, SPEC-007 is **Completed**. Update frontmatter and commit.

## Notes

- **The single biggest debugging tool is the `/.well-known` URLs.** When claude.ai's flow fails, the first thing to do is curl your own PRM and AS metadata URLs and confirm they look right for the URL claude.ai is talking to. Wrong `issuer`, mismatched `resource`, missing `S256` in `code_challenge_methods_supported` — all visible there.
- **Forwarded headers are subtle.** If your JWTs have `iss: http://localhost:3001` when they should have `iss: https://<app-fqdn>`, that's almost always because `ForwardedHeaders` middleware isn't picking up `X-Forwarded-Proto` and `X-Forwarded-Host` from Container Apps' ingress. Clearing `KnownNetworks`/`KnownProxies` is the fix (with the trust caveats — this is a single-tenant personal tool).
- **Cookie expiry vs token expiry.** Cookie auth (SPEC-006) is the *session*; JWT (SPEC-007) is the *delegation token*. When a JWT expires, claude.ai re-runs `/authorize`, which uses the still-valid cookie to silently issue a new code — the user never sees Google again until the cookie also expires (14 days default). Different lifetimes for different concerns.
- **Token shape inspection.** Paste any JWT you issue into https://jwt.io to verify claims. Useful sanity check, especially the first time. Don't paste production tokens into random websites once you're past the learning phase — jwt.io is operated by Auth0 and signed claims could theoretically leak. For ongoing inspection, `dotnet user jwt` or a local JWT decoder is safer.
- **Refresh tokens.** Skipped this slice. When you want them: add `refresh_token` to the `/token` response, store refresh-token records server-side, add a new branch in `/token` for `grant_type=refresh_token`, rotate the refresh on each use (issue new, invalidate old). Two new endpoints' worth of code; not a hidden monster.
- **Hashed client secret storage.** This slice does constant-time compare on cleartext from user-secrets. The more rigorous pattern is to store only PBKDF2 or bcrypt of the secret, never the cleartext. For a single client whose secret is already protected by being in user-secrets / Key Vault, the marginal benefit is small. Worth tightening if you ever expose this pattern beyond personal use.
- **DCR.** If at some point you want to support multiple MCP clients without manually pre-registering each, implement RFC 7591 Dynamic Client Registration — a `POST /register` endpoint that takes `redirect_uris`, issues a `client_id`/`client_secret`, and records the new client. Not blocking for personal use; standard for AS implementations.
- **Audience binding.** We're setting `aud` to `<base>/mcp` but `ValidateAudience = false` in the JWT bearer config. The right end-state is `ValidateAudience = true` with `ValidAudiences` populated from the actual server URL. Deferred because the dynamic-URL situation makes that awkward without picking a canonical URL; revisit when you decide to lock to the Container Apps FQDN as canonical.
- **Single replica required.** The in-memory `AuthorizationCodeStore` only works because Container Apps is configured with `max-replicas 1` (SPEC-003). Scaling out would require moving code storage to Redis or Table Storage. Worth knowing if you ever change that flag.
- **MCP Inspector with auth.** Inspector has a "Bearer Token" field in its connection UI; paste a JWT you generated via the curl flow to keep using Inspector against the protected `/mcp`. Token expires in 24h, so during a long dev session you may need to refresh it once.
