---
id: SPEC-006
topic: tidal-sonics
kind: spec
date: 2026-09-23
last_updated: 2026-09-23
status: Ready
depends_on:
  - SPEC-005
supersedes:
superseded_by:
adr: adr/ADR-006.md
reference: reference/SPEC-006.md
context_files:
  - src/TidalSonics.Server/Program.cs
  - src/TidalSonics.Server/appsettings.json
success_criteria:
  - Visiting `http://localhost:3001/signin` in a browser bounces through Google and lands on `/me` showing your email and name
  - Visiting `/signin` while already signed in skips the Google prompt and goes straight to `/me`
  - Visiting `/signout` clears the cookie; `/me` then returns 401
  - Signing in with a Google account that isn't in the allow-list redirects to `/access-denied` and does NOT create a session
  - The same browser flows work through the dev tunnel URL (HTTPS)
  - /mcp` continues to serve the `Hello` tool without authentication (SPEC-001 behavior preserved); Inspector and claude.ai connectors keep working unchanged
---

# SPEC-006: Google sign-in via OIDC federation

## ADR

Decisions and rationale for this slice live in [`adr/ADR-006.md`](../adr/ADR-006.md). Read it before starting; do not restate it here.

## Specs

### Spec 1: Google Cloud Console setup

Manual one-time steps in the Google Cloud Console at https://console.cloud.google.com/:

1. **Project.** Create a new project (or pick an existing personal one). Name: `tidal-sonics-auth`. Note the project ID.
2. **OAuth consent screen** (APIs & Services → OAuth consent screen):
   - User Type: **External**.
   - App name: `TIDAL Sonics`.
   - User support email: your Gmail.
   - Developer contact: your Gmail.
   - Scopes: leave default (`openid`, `email`, `profile` will be requested by the app at sign-in; no need to pre-add them on the consent screen).
   - Test users: add your Gmail.
   - Leave in **Testing** mode. Do not click "Publish app."
3. **Credentials** (APIs & Services → Credentials → Create credentials → OAuth client ID):
   - Application type: **Web application**.
   - Name: `TIDAL Sonics MCP Server`.
   - Authorized JavaScript origins: leave blank (server-side flow only).
   - Authorized redirect URIs: add all three of:
     - `http://localhost:3001/signin-google`
     - `https://<tunnel-id>-3001.<region>.devtunnels.ms/signin-google` (substitute your real tunnel hostname from SPEC-005)
     - `https://<app-fqdn>/signin-google` (substitute your Container Apps FQDN from SPEC-003)
   - Create. Copy the **Client ID** and **Client Secret** to a safe place (you'll paste them into user-secrets in Spec 3).

### Spec 2: Package

Add the Google authentication package:

```bash
cd src/TidalSonics.Server
dotnet add package Microsoft.AspNetCore.Authentication.Google
```

Cookie auth ships in-box with ASP.NET Core; no separate package needed.

### Spec 3: User-secrets configuration

Initialize user-secrets for the project and set the three values:

```bash
cd src/TidalSonics.Server
dotnet user-secrets init
dotnet user-secrets set "Google:ClientId" "<client-id-from-google>"
dotnet user-secrets set "Google:ClientSecret" "<client-secret-from-google>"
dotnet user-secrets set "Auth:AllowedEmails:0" "<your-gmail@gmail.com>"
```

`Auth:AllowedEmails:0` is the user-secrets indexed-array syntax for an array's first element. Add more with `:1`, `:2`, etc. — though for a single-user tool, one entry is the point.

Verify:

```bash
dotnet user-secrets list
```

Should show all three keys, with values present (the actual ClientSecret value displayed; that's fine — it's stored outside the repo).

### Spec 4: `appsettings.json` shape

Add the empty shape so the config keys are discoverable to a future reader of the repo (and so `IConfiguration.GetSection("Auth:AllowedEmails").Get<string[]>()` returns an empty array rather than null in environments where user-secrets isn't loaded):

> **Code lives in reference.** config (JSON) block 1 of `reference/SPEC-006.md` ("Spec 4: `appsettings.json` shape"). Write it yourself first; open the reference only if stuck.

(Existing keys like `Logging` and `AllowedHosts` carried forward unchanged from `dotnet new web`.)

### Spec 5: `Program.cs` — auth wiring

Add the authentication and authorization services before `builder.Build()`, and add `UseAuthentication()` / `UseAuthorization()` to the pipeline before `MapMcp()`:

> **Code lives in reference.** C# block 2 of `reference/SPEC-006.md` ("Spec 5: `Program.cs` — auth wiring"). Write it yourself first; open the reference only if stuck.
> Shape: `MapMcp()`

Several details that matter:

- `DefaultScheme = Cookies` so once the user has a cookie, `User.Identity.IsAuthenticated` reflects it.
- `DefaultChallengeScheme = Google` so when something challenges (we'll do this in `/signin`), the user is sent to Google.
- `SaveTokens = false`. We don't intend to call Google APIs on the user's behalf — we only need to know who they are. Skipping token storage avoids leaking unnecessary state into the cookie.
- The `OnTicketReceived` allow-list check runs after Google returns identity claims but before the cookie is issued. Calling `HandleResponse()` prevents the default sign-in.
- `UseAuthentication()` must come **before** `UseAuthorization()` and **before** `MapMcp()`. Order matters — middleware that reads `HttpContext.User` only sees populated values if `UseAuthentication` ran first.

### Spec 6: Sign-in endpoints

Add these immediately before `app.Run()`:

> **Code lives in reference.** C# block 3 of `reference/SPEC-006.md` ("Spec 6: Sign-in endpoints"). Write it yourself first; open the reference only if stuck.
> Shape: `GET /signin` · `GET /signout` · `GET /me` · `GET /access-denied`

The four endpoints:

- **`/signin`** — issues a Google challenge with a `RedirectUri` of `/me`. After Google returns and `OnTicketReceived` passes the allow-list check, the cookie is issued and the browser lands on `/me`.
- **`/signout`** — clears the auth cookie. Doesn't tell Google to sign out (that's a separate concern called RP-initiated logout; not needed for personal use).
- **`/me`** — returns identity claims as JSON. The "are we signed in" verification endpoint.
- **`/access-denied`** — minimal HTML page shown when the allow-list rejects you. Includes a `/signout` link so you can try with a different Google account without restart.

### Spec 7: Test plan

**Local sanity:**

1. Run `dotnet run --project src/TidalSonics.Server`.
2. Browser → `http://localhost:3001/me`. Expect 401.
3. Browser → `http://localhost:3001/signin`. Bounced to Google sign-in. Sign in with your allow-listed Gmail.
4. Browser lands on `http://localhost:3001/me`. Shows JSON with email, name, sub.
5. Browser → `http://localhost:3001/signout`. Cleared.
6. Browser → `http://localhost:3001/me`. Back to 401.

**Allow-list rejection:**

7. Browser → `http://localhost:3001/signin` in an incognito window. Sign in with a Google account that is NOT in the allow-list (e.g., a secondary Google account). Should redirect to `/access-denied`.
8. Confirm no cookie was set (devtools → Application → Cookies). Confirm `/me` still returns 401.

**Tunnel sanity:**

9. With `dotnet run` going and `devtunnel host $TUNNEL_ID` running, repeat steps 1–6 against the tunnel hostname (`https://<tunnel-id>-3001.<region>.devtunnels.ms/...`). Should behave identically.

**MCP regression check:**

10. Inspector against `http://localhost:3001/mcp` — `Hello` tool still works, no auth required.
11. claude.ai (either prod or dev connector) — `Hello` tool still works through a conversation.

If all eleven pass, SPEC-006 is **Completed**.

## Tasks

### Task 1: Google Cloud Console setup

Walk through Spec 1. Save the Client ID and Secret somewhere private (password manager). Don't commit them anywhere.

### Task 2: Add the Google auth package

Run `dotnet add package Microsoft.AspNetCore.Authentication.Google` from Spec 2.

### Task 3: Configure user-secrets

Initialize user-secrets and set the three values from Spec 3. Verify with `dotnet user-secrets list`. Commit nothing — user-secrets aren't in the repo by design.

### Task 4: Add the empty config shape

Edit `src/TidalSonics.Server/appsettings.json` to add the `Google` and `Auth` sections from Spec 4. Commit: `chore: add empty Google and Auth config shape`.

### Task 5: Wire up auth in `Program.cs`

Replace `Program.cs` with the content from Spec 5. Build to confirm it compiles. Commit: `feat: add cookie + Google authentication with email allow-list`.

### Task 6: Add the sign-in endpoints

Add the four endpoints from Spec 6 immediately before `app.Run()`. Commit: `feat: add /signin, /signout, /me, /access-denied endpoints`.

### Task 7: Run and test locally

Walk through Spec 7 steps 1–8. Capture any unexpected behavior in the spec body or in a TODO file before moving to the tunnel.

### Task 8: Test through the tunnel

Steps 9–11 of Spec 7. Confirm parity. Then update spec frontmatter `status` and commit.

## Notes

- **Google's localhost special case.** Google explicitly allows `http://localhost` redirect URIs without HTTPS for development. This is why we don't need HTTPS for the local server in SPEC-006. The tunnel URL is HTTPS anyway, and production (Container Apps) gives us HTTPS for free.
- **Cookie scopes and HTTPS.** ASP.NET Core's default `CookieSecurePolicy` is `SameAsRequest`, meaning the cookie sets `Secure` on HTTPS requests (tunnel, prod) and skips it on HTTP localhost. No additional config needed.
- **`OnTicketReceived` vs `OnCreatingTicket`.** Both events fire during the Google callback flow. `OnCreatingTicket` runs earlier (after token exchange, before the principal is built). `OnTicketReceived` runs after the principal is built but before sign-in. We use `OnTicketReceived` because the email claim is easier to read from the constructed principal than from raw response JSON.
- **Why no `[Authorize]` on `/me`?** With `[Authorize]` and `DefaultChallengeScheme = Google`, an unauthenticated GET to `/me` would immediately redirect to Google — too aggressive for a verification endpoint. The hand-rolled 401 lets you see "not signed in yet" clearly. When SPEC-007 introduces JWT alongside cookies, the default-scheme story gets more nuanced (different schemes for different routes), and that's the right time to revisit how `[Authorize]` is used.
- **Sign-out doesn't sign out of Google.** Calling `/signout` clears the app cookie but does NOT log the user out of Google itself. Hitting `/signin` again will silently re-authenticate via Google's existing session, skipping the prompt. That's intended for personal use; for multi-user contexts you'd implement RP-initiated logout that propagates to the IdP.
- **Tunnel URL stability is doing real work here.** Because Google requires exact redirect URI matches, a rotating tunnel URL would mean updating Google Cloud Console every session. SPEC-005's choice of persistent named tunnels means we register the redirect URI once and forget about it.
- **Production redirect URI registered now.** The Container Apps FQDN is registered with Google in Task 1 even though we won't exercise that flow until SPEC-007. Registering all three URIs up front is cheap and avoids context-switching later.
- **Testing-mode token refresh.** Google's docs warn that in Testing mode, refresh tokens expire after 7 days. Doesn't affect us this slice because we set `SaveTokens = false` and never use Google's refresh tokens. Will be relevant if/when we ever need a long-lived Google API session, which isn't on the roadmap.
