---
id: SPEC-009
topic: tidal-sonics
kind: spec
date: 2026-09-23
last_updated: 2026-09-23
status: Ready
depends_on:
  - SPEC-008
supersedes:
superseded_by:
adr: adr/ADR-009.md
reference: reference/SPEC-009.md
context_files:
  - src/TidalSonics.Server/Tidal/TidalTokenProvider.cs
  - src/TidalSonics.Server/Tidal/TidalCatalogClient.cs
  - src/TidalSonics.Server/Tools/SearchTool.cs
success_criteria:
  - TIDAL Developer app has `playlists.read playlists.write` (and any prerequisite) scopes enabled, plus a registered redirect URI for the local bootstrap
  - A one-time bootstrap script obtains an access token and refresh token using authorization_code + PKCE; tokens land in user-secrets
  - TidalUserTokenProvider` returns a valid user-context token, refreshing via `refresh_token` grant when the access token expires
  - find_playlist_by_name(name)` returns matching user playlists (id, name, track count) or an empty list
  - create_playlist(name, description?)` creates a playlist and returns its id and name
  - From claude.ai: a conversation can create a playlist and confirm it appears in TIDAL's UI
  - Search and Hello tools continue to work (no regression from the additional token provider)
---

# SPEC-009: `find_playlist_by_name` and `create_playlist` tools

## ADR

Decisions and rationale for this slice live in [`adr/ADR-009.md`](../adr/ADR-009.md). Read it before starting; do not restate it here.

## Specs

### Spec 1: TIDAL Developer Portal updates

1. https://developer.tidal.com → Manage apps → your TIDAL Sonics app.
2. Add Authorized redirect URI: `http://localhost:8888/tidal-bootstrap-callback`. (Localhost works fine for one-time bootstrap; TIDAL allows it.)
3. Confirm `playlists.read` and `playlists.write` are available scopes on your app. If they aren't visible in the app settings, you may need to request them or enable them — TIDAL's developer dashboard governs which scopes a given app is permitted to request.

### Spec 2: Bootstrap script `scripts/tidal-user-bootstrap.sh`

A one-shot helper that does the PKCE dance manually. Run it once; copy the printed `dotnet user-secrets set` lines into the project.

> **Code lives in reference.** shell script block 1 of `reference/SPEC-009.md` ("Spec 2: Bootstrap script `scripts/tidal-user-bootstrap.sh`"). Write it yourself first; open the reference only if stuck.

`chmod +x` it. Doesn't need committing as functional code — it's a personal-machine tool — but commit it as part of the repo so future-you (or a fresh laptop) can re-run it. Don't paste *outputs* into the repo.

Windows note: if you're not on a system with bash + openssl + python3, an equivalent PowerShell version is doable but longer. Bash via WSL is the simplest path; flagged in Notes.

### Spec 3: Cross-check endpoint paths

Before writing any C#, open https://developer.tidal.com/apiref?spec=user-playlist-v2 in a browser. Find the operations for:

- **Listing the authenticated user's playlists** — likely `GET /v2/playlists` with a filter for user, or `GET /v2/userCollections/me/playlists`. The exact path and filter syntax goes in Spec 5.
- **Creating a playlist** — likely `POST /v2/playlists` with a JSON:API request body. The exact required attributes (name, description, perhaps `accessType` / `visibility`) go in Spec 5.
- **Getting the authenticated user's ID** — needed only if list/create require a user ID in the path. If `me` works as a magic identifier, skip.

Capture the verified paths and request/response shapes; they replace the placeholders below.

### Spec 4: Configuration

Add to `appsettings.json`:

> **Code lives in reference.** config (JSON) block 2 of `reference/SPEC-009.md` ("Spec 4: Configuration"). Write it yourself first; open the reference only if stuck.

The bootstrap script populates `UserAccessToken` and `UserRefreshToken` in user-secrets.

Update `TidalOptions`:

> **Code lives in reference.** C# block 3 of `reference/SPEC-009.md` ("Spec 4: Configuration"). Write it yourself first; open the reference only if stuck.
> Shape: `record TidalOptions`

### Spec 5: `TidalUserTokenProvider`

Same shape as `TidalTokenProvider`, different grant. Reads `UserAccessToken` and `UserRefreshToken` from configuration at startup; mints new access tokens via `refresh_token` grant on demand.

> **Code lives in reference.** C# block 4 of `reference/SPEC-009.md` ("Spec 5: `TidalUserTokenProvider`"). Write it yourself first; open the reference only if stuck.
> Shape: `class TidalAuthExpiredException` · `class TidalUserTokenProvider` · `public async Task<string> GetAccessTokenAsync(…)`

The `_expiresAt = UtcNow` on construction forces the first call to refresh, validating that the stored refresh token still works before we ever try a real API call. Cleaner failure mode than discovering a stale refresh token mid-tool-call.

### Spec 6: `TidalUserAuthDelegatingHandler`

Same shape as the catalog handler (Spec 4 in SPEC-008), but pointed at the user token provider:

> **Code lives in reference.** C# block 5 of `reference/SPEC-009.md` ("Spec 6: `TidalUserAuthDelegatingHandler`"). Write it yourself first; open the reference only if stuck.
> Shape: `class TidalUserAuthDelegatingHandler`

We could DRY this and the catalog handler against a generic base. Not worth it — the two paths might diverge (e.g., different retry policies for user vs catalog), and clarity beats two-class generic plumbing at this size.

### Spec 7: `TidalPlaylistClient`

Endpoint paths and request bodies below are **best-effort placeholders**. Verify against the user-playlist-v2 spec (Task 3) and substitute the real shapes.

> **Code lives in reference.** C# block 6 of `reference/SPEC-009.md` ("Spec 7: `TidalPlaylistClient`"). Write it yourself first; open the reference only if stuck.
> Shape: `record PlaylistMatch` · `record CreatedPlaylist` · `class TidalPlaylistClient` · `public async Task<IReadOnlyList<PlaylistMatch>> FindByNameAsync(…)` · `public async Task<CreatedPlaylist> CreateAsync(…)`

The `JsonApiCollectionDocument` is a new DTO — JSON:API has a separate top-level shape for collections (`data` is an array) vs single resources (`data` is an object). Add to `Models/JsonApi.cs`:

> **Code lives in reference.** C# block 7 of `reference/SPEC-009.md` ("Spec 7: `TidalPlaylistClient`"). Write it yourself first; open the reference only if stuck.
> Shape: `record JsonApiCollectionDocument`

### Spec 8: DI registration

Extending the Tidal registrations from SPEC-008:

> **Code lives in reference.** C# block 8 of `reference/SPEC-009.md` ("Spec 8: DI registration"). Write it yourself first; open the reference only if stuck.

### Spec 9: `PlaylistTool`

> **Code lives in reference.** C# block 9 of `reference/SPEC-009.md` ("Spec 9: `PlaylistTool`"). Write it yourself first; open the reference only if stuck.
> Shape: `class PlaylistTool` · `public Task<IReadOnlyList<PlaylistMatch>> FindPlaylistByName(…)` · `public Task<CreatedPlaylist> CreatePlaylist(…)`

The tool descriptions cross-reference each other — this is the prompt that nudges the LLM toward find-then-create when appropriate, without bundling the two operations into one rigid tool.

### Spec 10: Validation

**Inspector test:**

`dotnet watch run`. With a JWT, Inspector against `http://localhost:3001/mcp`. Three tools listed: `Hello`, `SearchTracks`, `FindPlaylistByName`, `CreatePlaylist`. Call:

- `FindPlaylistByName` with the name of an existing playlist in your TIDAL library — expect a match.
- `FindPlaylistByName` with a clearly non-existent name — expect an empty list.
- `CreatePlaylist` with `"TIDAL Sonics test"` and a description — expect success, then check TIDAL's UI confirms the playlist exists.

**claude.ai dev test:**

> Using TIDAL Sonics (dev): do I have a playlist called "Late Night"? If not, create one with description "Songs for after midnight".

Confirm the LLM calls `find_playlist_by_name` first, then `create_playlist` if the find returned empty. If it skips straight to create, the tool descriptions need tightening.

**Token refresh test:**

Wait until your initial bootstrap-issued access token expires (24 hours after bootstrap) and try to call a playlist tool. The refresh path should fire silently. Tail logs for `TIDAL rotated the user refresh token` warnings — if you see one, paste the new refresh token into user-secrets for the next process restart.

**Prod deploy:**

```bash
export IMAGE_TAG=v4
az acr build -r $ACR_NAME -t tidal-sonics-server:$IMAGE_TAG -f Dockerfile .

az containerapp secret set -g $RG -n $APP_NAME \
  --secrets \
    "tidal-user-access-token=$ACCESS_FROM_BOOTSTRAP" \
    "tidal-user-refresh-token=$REFRESH_FROM_BOOTSTRAP"

az containerapp update -g $RG -n $APP_NAME \
  --image $ACR_LOGIN_SERVER/tidal-sonics-server:$IMAGE_TAG \
  --set-env-vars \
    Tidal__UserAccessToken=secretref:tidal-user-access-token \
    Tidal__UserRefreshToken=secretref:tidal-user-refresh-token
```

Then test through the prod connector.

## Tasks

### Task 1: Update TIDAL Developer Portal

Spec 1. Add the localhost redirect URI, confirm playlist scopes.

### Task 2: Add the bootstrap script

Create `scripts/tidal-user-bootstrap.sh` per Spec 2. `chmod +x`. Commit: `chore: add TIDAL user-token bootstrap script`.

### Task 3: Verify v2 user-playlist endpoint shapes

Spec 3. Open the TIDAL Developer Portal API reference for `user-playlist-v2`. Note the exact paths and request/response shapes for "list user playlists" and "create playlist." If they differ from the placeholders in Specs 5 and 7, adjust as needed when implementing.

### Task 4: Run the bootstrap

```bash
./scripts/tidal-user-bootstrap.sh
```

Walk through the browser dance. Paste the printed `dotnet user-secrets set` lines into the project. Verify with `dotnet user-secrets list`.

### Task 5: Extend `appsettings.json` and `TidalOptions`

Spec 4 changes. Commit: `chore: add Tidal user-token config shape`.

### Task 6: Implement `TidalUserTokenProvider`

`Tidal/TidalUserTokenProvider.cs` per Spec 5. Commit: `feat: add TidalUserTokenProvider with refresh_token grant`.

### Task 7: Implement `TidalUserAuthDelegatingHandler`

`Tidal/TidalUserAuthDelegatingHandler.cs` per Spec 6. Commit: `feat: add user-context auth handler with 401 retry`.

### Task 8: Add `JsonApiCollectionDocument`

Append to `Tidal/Models/JsonApi.cs` per Spec 7's note. Commit: `chore: add JSON:API collection document DTO`.

### Task 9: Implement `TidalPlaylistClient`

`Tidal/TidalPlaylistClient.cs` per Spec 7. Substitute verified endpoint paths from Task 3. Commit: `feat: add TidalPlaylistClient with find-by-name and create`.

### Task 10: DI registration

`Program.cs` per Spec 8. Build. Commit: `feat: register playlist client and user-context handler`.

### Task 11: Implement `PlaylistTool`

`Tools/PlaylistTool.cs` per Spec 9. Build. Commit: `feat: add find_playlist_by_name and create_playlist MCP tools`.

### Task 12: Inspector validation

Spec 10 Inspector section.

### Task 13: claude.ai (dev) validation

Spec 10 dev section. Particularly: verify the LLM uses find-then-create on idempotency prompts.

### Task 14: Token refresh validation

Spec 10 refresh section. Either wait the 24 hours, or — for a faster smoke test — manually clear the in-memory cache (restart the process) and confirm the first tool call triggers a refresh.

### Task 15: Deploy and prod-connector validation

Spec 10 prod section.

If all of the above pass, SPEC-009 is **Completed**.

## Notes

- **Endpoint paths in Spec 5 and 7 are best-effort.** The user-playlist-v2 spec page on TIDAL's developer portal couldn't be fully scraped from third-party indexes. Task 3 is the load-bearing verification step. JSON:API conventions are stable; what's likely to vary is exact path (`/playlists` vs `/userCollections/me/playlists` vs `/users/me/playlists`), filter syntax, and the `accessType` enum values (`UNLISTED` vs `PRIVATE` vs `PUBLIC`).
- **`r_usr` scope is v1, not v2.** TIDAL's forum threads include developers tripping over this — `r_usr` returns 403 from v2 endpoints, and conversely `playlists.read playlists.write` won't work against the v1 user endpoints. Pure v2 scopes only for our use case.
- **Refresh-token rotation, persistence.** The `TidalUserTokenProvider` logs a warning with the new refresh token when it rotates, but doesn't persist it anywhere. Process restart → fall back to user-secrets → may be stale → refresh fails → re-bootstrap. This friction goes away once SPEC-011 (Key Vault) and SPEC-012 (full `/connect-tidal` automation) land. For SPEC-009, accept the friction.
- **PowerShell bootstrap.** If you're not running bash, a PowerShell equivalent is straightforward — `Get-Random`, `[Convert]::ToBase64String([System.Security.Cryptography.SHA256]::Create().ComputeHash(...))`, `Invoke-WebRequest`. Worth writing alongside the bash version if you regularly switch shells; not in this slice's scope.
- **The "redirect fails in browser" UX.** Could be smoothed by having the bootstrap script spin up a brief HTTP listener on 8888 that captures the redirect automatically. `python3 -m http.server` or `nc -l` get you most of the way; ASP.NET `WebApplication.CreateBuilder(args).Run("http://localhost:8888")` works in a few lines. Skipped for simplicity; the manual copy-paste is one extra step but fewer moving parts.
- **`numberOfItems` vs `trackCount` vs `length`.** The exact attribute name for "how many tracks are in this playlist" varies across TIDAL's APIs. My placeholder uses `numberOfItems` based on JSON:API resource conventions in similar music services; verify against the actual spec.
- **Container Apps secrets keep growing.** SPEC-007 added `tidal-client-id` / `tidal-client-secret`; SPEC-008 inherited; this slice adds `tidal-user-access-token` and `tidal-user-refresh-token`. By SPEC-011 we'll have a half dozen and Key Vault is the right place. Until then, native Container Apps secrets are fine.
- **Don't put the user tokens in claude.ai's connector config.** They're TIDAL credentials, not our server's auth — they belong on the server side only. claude.ai's only credential for our server is the OAuth client_secret from SPEC-007. Keep these two secret stores mentally separate.
- **Single tool description doing double duty.** The `find_playlist_by_name` and `create_playlist` descriptions reference each other — this is deliberate. The LLM reads both descriptions when it has both tools available, and the cross-reference is what shapes the "find-first-when-asked-to-add-to-existing" behavior. If you split this into two unrelated specs in the future, watch out for the descriptions drifting apart.
