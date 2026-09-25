---
id: SPEC-012
topic: tidal-sonics
kind: spec
date: 2026-09-23
last_updated: 2026-09-23
status: Ready
depends_on:
  - SPEC-011
supersedes:
superseded_by:
adr: adr/ADR-012.md
reference: reference/SPEC-012.md
context_files:
  - src/TidalSonics.Server/Program.cs
  - src/TidalSonics.Server/Tidal/TidalUserTokenProvider.cs
  - src/TidalSonics.Server/Tidal/TidalSecretStore.cs
success_criteria:
  - Visiting `https://<app-fqdn>/connect-tidal` while signed in via Google bounces through TIDAL's OAuth flow and lands on `/tidal-connected`
  - The TIDAL access token and refresh token end up in Key Vault automatically; the previously-running `TidalUserTokenProvider` picks up the new tokens without a process restart
  - Anyone hitting `/connect-tidal` without a valid cookie gets bounced through Google sign-in first (allow-list of one applies)
  - Re-running `/connect-tidal` cleanly rotates tokens (idempotent — no special handling needed)
  - TIDAL OAuth errors (user denies consent, code expires, etc.) land on `/tidal-error` with a clear message rather than a stack trace
  - The `scripts/tidal-user-bootstrap.sh` from SPEC-009 still works as a local fallback, but is no longer required for normal operation
---

# SPEC-012: `/connect-tidal` bootstrap route

## ADR

Decisions and rationale for this slice live in [`adr/ADR-012.md`](../adr/ADR-012.md). Read it before starting; do not restate it here.

## Specs

### Spec 1: TIDAL Developer Portal redirect URIs

In the TIDAL Developer Portal, on the TIDAL Sonics app, add to Authorized redirect URIs:

- `https://<tunnel-id>-3001.<region>.devtunnels.ms/tidal-callback` (your actual dev tunnel hostname)
- `https://<app-fqdn>/tidal-callback` (your Container Apps FQDN)

Keep `http://localhost:8888/tidal-bootstrap-callback` from SPEC-009 if you want the script as a fallback; remove it if you want a single source of truth.

### Spec 2: `PkceStateStore`

> **Code lives in reference.** C# block 1 of `reference/SPEC-012.md` ("Spec 2: `PkceStateStore`"). Write it yourself first; open the reference only if stuck.
> Shape: `record PkceState` · `class PkceStateStore` · `public void Add(…)` · `public PkceState? TakeIfValid(…)`

Take-once semantics (`TryRemove`) prevent code-injection replay. The `ReturnUrl` field is unused this slice (we always redirect to `/tidal-connected` on success) but included for symmetry with SPEC-007's `AuthorizationCodeStore` and in case a future variant wants to redirect somewhere specific after.

Register as singleton in `Program.cs`:

> **Code lives in reference.** C# block 2 of `reference/SPEC-012.md` ("Spec 2: `PkceStateStore`"). Write it yourself first; open the reference only if stuck.

### Spec 3: Extend `ITidalSecretStore`

Add a method that updates both tokens together:

> **Code lives in reference.** C# block 3 of `reference/SPEC-012.md` ("Spec 3: Extend `ITidalSecretStore`"). Write it yourself first; open the reference only if stuck.
> Shape: `interface ITidalSecretStore`

KV implementation:

> **Code lives in reference.** C# block 4 of `reference/SPEC-012.md` ("Spec 3: Extend `ITidalSecretStore`"). Write it yourself first; open the reference only if stuck.
> Shape: `class KeyVaultTidalSecretStore` · `public Task UpdateRefreshTokenAsync(…)` · `public async Task UpdateUserTokensAsync(…)`

No-op implementation:

> **Code lives in reference.** C# block 5 of `reference/SPEC-012.md` ("Spec 3: Extend `ITidalSecretStore`"). Write it yourself first; open the reference only if stuck.
> Shape: `class NoopTidalSecretStore` · `public Task UpdateRefreshTokenAsync(…)` · `public Task UpdateUserTokensAsync(…)`

The no-op logs the exact CLI commands you'd need — the SPEC-009 friction in a slightly nicer form, since you got here via a browser instead of a shell script.

### Spec 4: `TidalUserTokenProvider.Reload`

Add a public method to push new tokens into the running provider:

> **Code lives in reference.** C# block 6 of `reference/SPEC-012.md` ("Spec 4: `TidalUserTokenProvider.Reload`"). Write it yourself first; open the reference only if stuck.
> Shape: `public void Reload(…)`

Calling `Reload` from the callback handler is what makes the new tokens live immediately — without it, the in-memory cache from before the re-auth would still be used until the access token expired, defeating the point.

### Spec 5: `/connect-tidal` endpoint

Authentication-gated (cookie scheme from SPEC-006), generates PKCE pair, stores verifier, builds the TIDAL authorize URL, redirects:

> **Code lives in reference.** C# block 7 of `reference/SPEC-012.md` ("Spec 5: `/connect-tidal` endpoint"). Write it yourself first; open the reference only if stuck.
> Shape: `GET /connect-tidal`

A tiny helper at the bottom — same base64url encoding we'd use in the SPEC-007 `/token` endpoint's PKCE verification, only here for the challenge generation.

### Spec 6: `/tidal-callback` endpoint

Receives the code, validates state, exchanges code for tokens, persists to KV, reloads the provider:

> **Code lives in reference.** C# block 8 of `reference/SPEC-012.md` ("Spec 6: `/tidal-callback` endpoint"). Write it yourself first; open the reference only if stuck.
> Shape: `GET /tidal-callback`

Order of operations matters: persist to KV *before* calling `Reload`. If the persistence fails, the in-memory state stays on the old (still-working) tokens, and the error page tells the user what happened. Once persistence succeeds, the `Reload` call makes the new tokens live.

### Spec 7: `/tidal-connected` success page

> **Code lives in reference.** C# block 9 of `reference/SPEC-012.md` ("Spec 7: `/tidal-connected` success page"). Write it yourself first; open the reference only if stuck.
> Shape: `GET /tidal-connected`

### Spec 8: Validation

**Local-via-tunnel test:**

`dotnet watch run`, `devtunnel host $TUNNEL_ID`. In a browser:

1. Visit `https://<tunnel-id>-3001.<region>.devtunnels.ms/connect-tidal`.
2. If not already signed in via Google, get bounced through Google sign-in (allow-list check applies).
3. Then bounced to TIDAL's authorize page. Sign in / approve.
4. TIDAL redirects to `https://<tunnel>/tidal-callback?code=...&state=...`.
5. Server exchanges, persists, reloads, redirects to `/tidal-connected`.

Locally, the secret store is the no-op variant, so check Container Apps logs (or the local `dotnet run` console) for the `dotnet user-secrets set` lines.

Then call a playlist tool through claude.ai (dev connector). It should work without restart — confirming the `Reload` path is wired correctly. If you restart `dotnet watch` afterwards, you'd need to update user-secrets manually with the logged values (or just re-run `/connect-tidal`).

**Prod test:**

```bash
export IMAGE_TAG=v7
az acr build -r $ACR_NAME -t tidal-sonics-server:$IMAGE_TAG -f Dockerfile .
az containerapp update -g $RG -n $APP_NAME \
  --image $ACR_LOGIN_SERVER/tidal-sonics-server:$IMAGE_TAG
```

Then visit `https://<app-fqdn>/connect-tidal`. Walk through the same flow. After landing on `/tidal-connected`, verify:

```bash
az keyvault secret show --vault-name $KV_NAME --name "Tidal--UserAccessToken" --query "updated" -o tsv
az keyvault secret show --vault-name $KV_NAME --name "Tidal--UserRefreshToken" --query "updated" -o tsv
```

The `updated` timestamps should be from just now. Then call a playlist tool through claude.ai (prod connector) — works immediately, no app restart.

**Error path tests:**

- Visit `/connect-tidal` while signed out of Google. Confirm bounce to Google.
- Sign in with a non-allow-listed account, attempt `/connect-tidal`. Confirm `/access-denied` page (the SPEC-006 allow-list check fires).
- Visit `/tidal-callback` directly with no query string. Confirm the error page.
- Start a flow, wait six minutes, complete it. Confirm the state-expired error page.

## Tasks

### Task 1: Update TIDAL Developer Portal

Spec 1. Add the tunnel and prod redirect URIs.

### Task 2: Implement `PkceStateStore`

Spec 2. Commit: `feat: add PkceStateStore for OAuth state tracking`.

### Task 3: Extend `ITidalSecretStore` and `TidalUserTokenProvider`

Spec 3 + Spec 4. Both implementations of the interface get the new method; `TidalUserTokenProvider.Reload` is added. Commit: `feat: support full token rotation via secret store and provider reload`.

### Task 4: Implement `/connect-tidal`

Spec 5. Build. Commit: `feat: add /connect-tidal route initiating TIDAL OAuth flow`.

### Task 5: Implement `/tidal-callback`

Spec 6. Includes the error-page helper. Build. Commit: `feat: add /tidal-callback route completing TIDAL OAuth flow`.

### Task 6: Implement `/tidal-connected`

Spec 7. Commit: `feat: add /tidal-connected success page`.

### Task 7: DI registration

Confirm in `Program.cs`:
- `PkceStateStore` registered as singleton
- `ITidalSecretStore` registered conditionally (already done in SPEC-011)
- `TidalUserTokenProvider` already registered (SPEC-009)

Build. Commit if any registration changes were needed: `chore: wire PkceStateStore registration`.

### Task 8: Local validation via tunnel

Spec 8 local section. Walk through the full flow. Tail console logs.

### Task 9: Deploy and prod validation

Spec 8 prod section. Verify KV secrets updated. Then exercise a playlist tool through the prod claude.ai connector to confirm `Reload` worked.

### Task 10: Error-path validation

Spec 8 error-path tests. Useful to do at least once for confidence; not strictly required.

If all of the above pass, SPEC-012 is **Completed**. **The project is now operationally complete** — re-auth is browser-driven, secrets persist automatically, no shell scripts in normal operation.

## Notes

- **The project ends here, by design.** The original goal was "automate the manual playlist-copying step at the end of music recommendation chats." SPEC-010 hit that goal. SPEC-011 and SPEC-012 are polish that I'd argue you should only do if the original goal continues to feel valuable — they don't change *what* the project does, only *how cleanly* it does it. If the project ends up being a one-month curiosity, stopping at SPEC-010 was the right call. If it becomes a daily tool, you'll appreciate the work in 011/012.
- **Local re-auth still has friction.** The no-op `ITidalSecretStore` logs the `dotnet user-secrets set` commands; you still copy-paste them if you want the new tokens to survive a `dotnet watch` restart. Closing this gap would require either pointing local dev at the prod KV (security regression) or implementing a file-based local secret store (more moving parts). For a personal tool, the friction is minor and bounded.
- **`Reload` is the small but load-bearing change.** Without it, `/connect-tidal` would write to KV correctly, but the running process's `TidalUserTokenProvider` would still hold the previous tokens in memory until they expired. So you'd successfully re-auth, walk away thinking it worked, then have a tool call fail an hour later because the in-memory state was stale. Including `Reload` is what makes the UX feel like "this just works."
- **PKCE state lifetime: 5 minutes.** That's the OAuth flow time budget. Plenty for a normal human walking through TIDAL's consent screen; tight enough that abandoned flows clean themselves up. The state dict will accumulate entries for abandoned flows until they expire — at our usage volume, completely fine. If this ever became a multi-user public service, you'd want a background sweep to evict.
- **Cookie scheme on `[Authorize]`.** The `/connect-tidal` route uses `[Authorize(AuthenticationSchemes = CookieAuthenticationDefaults.AuthenticationScheme)]` rather than the JWT scheme used on `/mcp`. Two different schemes coexist on the server — JWT for machine-to-machine MCP calls, Cookie for human browser flows. The default-scheme handling from SPEC-006/007 makes this work cleanly.
- **TIDAL refresh token rotation is now fully closed.** Before this slice: rotate → log warning → manually update user-secrets → restart picks it up. After SPEC-011: rotate → write to KV automatically → restart picks it up from KV. After SPEC-012: rotate → write to KV → in-memory state reloaded → no restart needed. Three slices to close one loop, but each slice paid for itself in other ways too.
- **What `/connect-tidal` does NOT do.** It doesn't validate that the resulting tokens *work* — we just trust TIDAL's `expires_in` response. A more paranoid implementation would make a test call (e.g. fetch the user profile) after `Reload` and surface failure on the success page. Skipped for simplicity; if you ever hit a case where tokens come back but don't actually work, that's the place to add the check.
- **The script lives on as a fallback.** `scripts/tidal-user-bootstrap.sh` still works. Useful in two scenarios: (1) first-time setup before the server is deployed, (2) if the server itself is broken in a way that prevents `/connect-tidal` from working. Costs nothing to keep.
- **And we're done.** Whatever's parked in HANDOFF.md (DCR, refresh tokens for the AS, JWKS, dry_run, MCP Prompts, IP allowlisting, Bicep, chiseled images, CI/CD) is genuinely optional. The project is at a natural stopping point.
