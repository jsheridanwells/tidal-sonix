---
id: SPEC-008
topic: tidal-sonics
kind: spec
date: 2026-09-23
last_updated: 2026-09-23
status: Ready
depends_on:
  - SPEC-007
supersedes:
superseded_by:
adr: adr/ADR-008.md
reference: reference/SPEC-008.md
context_files:
  - src/TidalSonics.Server/Program.cs
  - src/TidalSonics.Server/Tools/HelloTool.cs
success_criteria:
  - A TIDAL Developer app is registered; `client_id` and `client_secret` live in user-secrets
  - TidalTokenProvider` mints a client-credentials access token on first use, caches it, and re-mints on 401 or near-expiry
  - search_tracks(query, limit?)` MCP tool returns a list of top-N matching tracks (id, title, artists, duration) for a free-form query
  - Calling the tool from claude.ai with a music-style query returns plausibly-matching TIDAL tracks
  - Tool description nudges the model to surface multiple candidates and disambiguate with me rather than picking
  - The `Hello` tool still works (no regression from auth or tool registration changes)
---

# SPEC-008: `search_tracks` tool against TIDAL Catalog v2

## ADR

Decisions and rationale for this slice live in [`adr/ADR-008.md`](../adr/ADR-008.md). Read it before starting; do not restate it here.

## Specs

### Spec 1: Register a TIDAL Developer app

One-time manual setup at https://developer.tidal.com:

1. Sign in (TIDAL account required; trial works).
2. Manage apps → Create app. Pick "Web Application" style. Name: `TIDAL Sonics`.
3. Capture the **Client ID** and **Client Secret**. The secret is shown once — save it.
4. For SPEC-008 you don't need a redirect URI configured (client_credentials doesn't redirect). For SPEC-009 you'll add `http://localhost:3001/tidal-callback` and the equivalent tunnel/prod URIs.

### Spec 2: Configuration

Add to user-secrets:

```bash
cd src/TidalSonics.Server
dotnet user-secrets set "Tidal:ClientId" "<tidal-client-id>"
dotnet user-secrets set "Tidal:ClientSecret" "<tidal-client-secret>"
```

Add shape to `appsettings.json`:

> **Code lives in reference.** config (JSON) block 1 of `reference/SPEC-008.md` ("Spec 2: Configuration"). Write it yourself first; open the reference only if stuck.

### Spec 3: `TidalTokenProvider`

Mints + caches a client-credentials access token. Singleton; thread-safe.

> **Code lives in reference.** C# block 2 of `reference/SPEC-008.md` ("Spec 3: `TidalTokenProvider`"). Write it yourself first; open the reference only if stuck.
> Shape: `class TidalTokenProvider` · `public async Task<string> GetAccessTokenAsync(…)` · `record TidalOptions`

Double-check semantics: the cached token is returned without locking; only on cache miss or forced refresh do we take the gate, recheck (double-checked locking pattern), and mint.

### Spec 4: `TidalAuthDelegatingHandler`

Adds the Bearer token to every outgoing request and forces one retry on 401:

> **Code lives in reference.** C# block 3 of `reference/SPEC-008.md` ("Spec 4: `TidalAuthDelegatingHandler`"). Write it yourself first; open the reference only if stuck.
> Shape: `class TidalAuthDelegatingHandler`

### Spec 5: JSON:API DTOs

Narrow surface, just what we need:

> **Code lives in reference.** C# block 4 of `reference/SPEC-008.md` ("Spec 5: JSON:API DTOs"). Write it yourself first; open the reference only if stuck.
> Shape: `record JsonApiDocument` · `record JsonApiResource` · `record JsonApiRelationship` · `record JsonApiRef`

Why `JsonElement` for `attributes` and `relationship.data`? JSON:API allows attributes to be arbitrarily shaped per type, and relationship `data` can be either an object (to-one) or an array (to-many). Strongly typing every variant balloons the model; `JsonElement` keeps the deserialization permissive and we read with `GetProperty` where needed.

### Spec 6: `TidalCatalogClient`

The actual API consumer. One method for SPEC-008; `find_playlist_by_name` and friends will live alongside it in later specs.

> **Code lives in reference.** C# block 5 of `reference/SPEC-008.md` ("Spec 6: `TidalCatalogClient`"). Write it yourself first; open the reference only if stuck.
> Shape: `class TidalCatalogClient` · `public async Task<IReadOnlyList<TrackMatch>> SearchTracksAsync(…)` · `record TrackMatch`

### Spec 7: HttpClient and DI registration

In `Program.cs`, after the existing service registrations:

> **Code lives in reference.** C# block 6 of `reference/SPEC-008.md` ("Spec 7: HttpClient and DI registration"). Write it yourself first; open the reference only if stuck.

Two `HttpClient` registrations: one named (`TidalAuth`) for the token endpoint, one typed (`TidalCatalogClient`) for the catalog. The token endpoint must NOT inherit the Bearer handler — it uses Basic auth.

### Spec 8: `SearchTool`

> **Code lives in reference.** C# block 7 of `reference/SPEC-008.md` ("Spec 8: `SearchTool`"). Write it yourself first; open the reference only if stuck.
> Shape: `class SearchTool` · `public async Task<IReadOnlyList<TrackMatch>> SearchTracks(…)`

The tool description is the prompt that ships to the model on every conversation that has the connector enabled. The "TIDAL search often returns the right track in positions 2-5" line is empirical (it's what makes the disambiguation worth doing); the "do not silently pick the first result" is the load-bearing instruction.

Static vs instance method choice: `Hello` (SPEC-001) was static; this one is instance because it needs DI for `TidalCatalogClient`. The MCP SDK supports both via `[McpServerTool]` discovery.

### Spec 9: Validation

**Curl test of TIDAL plumbing** (independent of MCP):

```bash
export TIDAL_CLIENT_ID=...
export TIDAL_CLIENT_SECRET=...
export B64=$(echo -n "${TIDAL_CLIENT_ID}:${TIDAL_CLIENT_SECRET}" | base64)

# Mint a token directly
curl -s -X POST https://auth.tidal.com/v1/oauth2/token \
  -H "Authorization: Basic $B64" \
  -d grant_type=client_credentials | jq .

export TOKEN=<paste access_token>

# Try a search
curl -s "https://openapi.tidal.com/v2/searchresults/radiohead%20pyramid%20song?countryCode=US&include=tracks,tracks.artists" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/vnd.api+json" | jq . | less
```

Confirm the response includes a `data.relationships.tracks` list and an `included` array with track + artist entities. This proves your client_id/secret and the endpoint shape, independent of any C# code.

**Inspector test:**

Run the server (`dotnet watch run`), open MCP Inspector with a JWT (from SPEC-007's curl flow), connect to `http://localhost:3001/mcp`. Two tools should be listed: `Hello` and `SearchTracks`. Invoke `SearchTracks` with `{ "query": "radiohead pyramid song", "limit": 5 }`. Confirm a structured result with 5 entries: ids, titles, artists, durations.

**claude.ai test:**

In a new conversation with the "TIDAL Sonics (dev)" connector enabled:

> Use TIDAL Sonics to search for "boards of canada roygbiv". Show me the candidates.

Confirm Claude calls the tool and surfaces multiple matches with artist/title rather than just saying "I picked the first one." If Claude does pick the first one without asking, refine the tool description and redeploy / restart `dotnet watch`.

Then via the prod connector (full Container Apps deploy):

```bash
# build + push a new image tag
export IMAGE_TAG=v3
az acr build -r $ACR_NAME -t tidal-sonics-server:$IMAGE_TAG -f Dockerfile .
az containerapp update -g $RG -n $APP_NAME \
  --image $ACR_LOGIN_SERVER/tidal-sonics-server:$IMAGE_TAG \
  --set-env-vars Tidal__ClientId=secretref:tidal-client-id Tidal__ClientSecret=secretref:tidal-client-secret
```

Wait — secrets in prod aren't in user-secrets, they're not yet in Key Vault either. For this slice, set Container Apps secrets directly via `az containerapp secret set` and reference them via `--set-env-vars`. Real Key Vault wiring is SPEC-011.

```bash
az containerapp secret set -g $RG -n $APP_NAME \
  --secrets "tidal-client-id=$TIDAL_CLIENT_ID" "tidal-client-secret=$TIDAL_CLIENT_SECRET"
az containerapp update -g $RG -n $APP_NAME \
  --set-env-vars Tidal__ClientId=secretref:tidal-client-id Tidal__ClientSecret=secretref:tidal-client-secret
```

(The double underscore `__` is .NET configuration's separator for nested keys in environment variables — maps to `Tidal:ClientId`.)

Then test `search_tracks` via the prod connector in a fresh claude.ai conversation.

## Tasks

### Task 1: Register the TIDAL Developer app

Walk through Spec 1. Save the Client ID and Secret in a password manager.

### Task 2: Configure user-secrets and `appsettings.json`

Spec 2 commands and JSON. Commit `appsettings.json` change: `chore: add Tidal config shape`.

### Task 3: Curl-test the TIDAL API path

Run Spec 9's curl commands. Confirm token minting works and `/searchresults` returns the expected JSON:API document shape. This is your sanity check on the developer-portal-side configuration before any C# code is written.

### Task 4: Create the `Tidal/` folder and `TidalOptions`

`src/TidalSonics.Server/Tidal/TidalOptions.cs` per Spec 3. Commit: `chore: scaffold Tidal namespace and options`.

### Task 5: Implement `TidalTokenProvider`

`Tidal/TidalTokenProvider.cs` per Spec 3. Build. Commit: `feat: add TidalTokenProvider for client-credentials flow`.

### Task 6: Implement `TidalAuthDelegatingHandler`

`Tidal/TidalAuthDelegatingHandler.cs` per Spec 4. Commit: `feat: add Bearer-attaching delegating handler with 401 retry`.

### Task 7: Implement JSON:API DTOs

`Tidal/Models/JsonApi.cs` (or split across files) per Spec 5. Commit: `feat: add minimal JSON:API DTOs for TIDAL responses`.

### Task 8: Implement `TidalCatalogClient` and `TrackMatch`

`Tidal/TidalCatalogClient.cs` per Spec 6. Commit: `feat: add TidalCatalogClient with SearchTracksAsync`.

### Task 9: Wire DI in `Program.cs`

Spec 7 changes. Build. Commit: `feat: register Tidal HttpClients and DI`.

### Task 10: Implement the `SearchTracks` tool

`src/TidalSonics.Server/Tools/SearchTool.cs` per Spec 8. Build. Commit: `feat: add SearchTracks MCP tool`.

### Task 11: Inspector validation

Spec 9 Inspector section. Confirm two tools listed, search returns plausible results.

### Task 12: claude.ai (dev) validation

Through the "TIDAL Sonics (dev)" connector, with a real-world music query. Confirm Claude surfaces multiple candidates and asks for disambiguation rather than picking #1.

### Task 13: Deploy and prod-connector validation

Spec 9's prod section: `az acr build`, `az containerapp secret set`, `az containerapp update`, then test through the "TIDAL Sonics" prod connector. Commit infra script changes if any.

If all of the above pass, SPEC-008 is **Completed**.

## Notes

- **JSON:API is unusual if you haven't seen it before.** The `data` + `included` split lets a response sideload related entities without re-fetching them. We use `include=tracks,tracks.artists` to get everything in one round-trip. The `relationships` object on each entity points (by `type`+`id`) at items in `included`. The `JsonElement` in our DTOs is intentional permissiveness — we don't model the entire JSON:API surface, just the bits we read.
- **TIDAL rate limits are tighter than you'd expect for a developer tier.** Discussion threads mention something like 2 requests per 10 seconds. The whole point of including artists in the search call (vs. fanning out to `/v2/tracks/{id}` per result) is to stay inside that budget. If you ever do need to do multiple sequential calls, add throttling.
- **Country code matters.** TIDAL gates content regionally. A track that exists in `countryCode=US` may not in `countryCode=DE`. Configurable, but for personal use pinning to your country is fine. If a search returns nothing for an obvious query, that's the first thing to check.
- **Two SPEC tools, two grant types.** Search uses client_credentials (catalog data, no user context). Playlists (SPEC-009+) use authorization_code with PKCE (user-context). Don't try to unify them — they're genuinely different grants with different lifecycles and different scopes.
- **Container Apps secrets vs Key Vault.** This slice uses Container Apps' built-in secret store (`az containerapp secret set`). That's fine — it's encrypted at rest, managed by the platform. SPEC-011 migrates to Key Vault, which (a) is the consistent home for *all* the project's secrets including the RSA signing key, (b) supports rotation hooks. Until then, Container Apps secrets are pragmatic.
- **Why instance method, not static, for `SearchTracks`?** It needs `TidalCatalogClient` from DI. Static would force a service locator pattern (`IServiceProvider.GetRequiredService`), which is anti-idiomatic in modern .NET. The MCP SDK handles instance methods just fine — `WithToolsFromAssembly()` finds them.
- **Token expiry and clock skew.** The 60-second leeway in `TidalTokenProvider` is overkill for client-credentials (no PKCE clock-skew concerns), but harmless and consistent with patterns we'll use for user-context tokens in SPEC-009.
- **Persisting the TIDAL token across restarts.** We don't. Process restart re-mints. With a 24-hour TTL, this means a maximum of one extra token request per restart — negligible. Persisting (Key Vault, file, Redis) would be premature.
- **Test scaffolding for TIDAL integration.** Deferred. When you do add tests, the natural shape is: a `TidalCatalogClient` test that uses a fake `HttpMessageHandler` to assert request shapes, and JSON fixtures captured from real responses to test `ProjectTracks`.
