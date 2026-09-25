---
id: SPEC-010
topic: tidal-sonics
kind: spec
date: 2026-09-23
last_updated: 2026-09-23
status: Ready
depends_on:
  - SPEC-009
supersedes:
superseded_by:
adr: adr/ADR-010.md
reference: reference/SPEC-010.md
context_files:
  - src/TidalSonics.Server/Tidal/TidalPlaylistClient.cs
  - src/TidalSonics.Server/Tools/PlaylistTool.cs
success_criteria:
  - TidalPlaylistClient.AddTracksAsync(playlistId, trackIds)` adds tracks to an existing playlist, batching transparently when the list exceeds the configured batch size
  - add_tracks_to_playlist` MCP tool is callable from claude.ai with a playlist id and a list of track ids
  - In one claude.ai conversation, the full pipeline works end-to-end: search_tracks` → `find_playlist_by_name` (or `create_playlist`) → `add_tracks_to_playlist`, with the resulting playlist visible in TIDAL's UI
  - Inter-batch delay prevents rate-limit failures on lists of 40+ tracks
  - Pre-existing tools (`Hello`, `SearchTracks`, `FindPlaylistByName`, `CreatePlaylist`) continue to work
---

# SPEC-010: `add_tracks_to_playlist` tool

## ADR

Decisions and rationale for this slice live in [`adr/ADR-010.md`](../adr/ADR-010.md). Read it before starting; do not restate it here.

## Specs

### Spec 1: Verify endpoint against the user-playlist-v2 spec

Open https://developer.tidal.com/apiref?spec=user-playlist-v2 and locate the "add tracks" / "add items" / "create playlist items" operation. Note:

- Exact path (the placeholder is `POST /v2/playlists/{id}/relationships/items`).
- Whether the resource type in the JSON:API refs is `"tracks"`, `"items"`, or something else.
- Whether the body needs additional metadata (e.g. positional hints, a wrapping `meta` object).
- Whether the response is JSON:API or just a 204.
- Any documented batch-size limits.

Adjust Specs 3 and 4 below if reality differs.

### Spec 2: Configuration

Extend the `Tidal` section in `appsettings.json`:

> **Code lives in reference.** config (JSON) block 1 of `reference/SPEC-010.md` ("Spec 2: Configuration"). Write it yourself first; open the reference only if stuck.

Update `TidalOptions`:

> **Code lives in reference.** C# block 2 of `reference/SPEC-010.md` ("Spec 2: Configuration"). Write it yourself first; open the reference only if stuck.
> Shape: `record TidalOptions`

### Spec 3: `AddTracksAsync` on `TidalPlaylistClient`

Add the result type and the method. Result captures success/failure cleanly so the tool's caller (the LLM) has enough information to react:

> **Code lives in reference.** C# block 3 of `reference/SPEC-010.md` ("Spec 3: `AddTracksAsync` on `TidalPlaylistClient`"). Write it yourself first; open the reference only if stuck.
> Shape: `record AddTracksResult`

Then on `TidalPlaylistClient` (which needs `TidalOptions` injected — adjust the constructor):

> **Code lives in reference.** C# block 4 of `reference/SPEC-010.md` ("Spec 3: `AddTracksAsync` on `TidalPlaylistClient`"). Write it yourself first; open the reference only if stuck.
> Shape: `class TidalPlaylistClient` · `public async Task<AddTracksResult> AddTracksAsync(…)`

The LINQ-based batching reads more naturally than a manual index loop and the perf cost is negligible at our scales.

### Spec 4: `AddTracksToPlaylist` tool

Append to `PlaylistTool.cs`:

> **Code lives in reference.** C# block 5 of `reference/SPEC-010.md` ("Spec 4: `AddTracksToPlaylist` tool"). Write it yourself first; open the reference only if stuck.
> Shape: `public Task<AddTracksResult> AddTracksToPlaylist(…)`

The description does three jobs at once: tells the model where IDs come from (provenance discipline), tells it where the playlist ID comes from (composition with the other tools), and discloses TIDAL's duplicate behavior (so the LLM can manage state within the conversation if asked to dedupe).

### Spec 5: Validation

**Inspector — atomic test:**

`dotnet watch run`. With a JWT, Inspector against `localhost:3001/mcp`. Pick a known good track ID (from a prior `SearchTracks` call) and a known good playlist ID (from `CreatePlaylist`). Call `AddTracksToPlaylist`. Expect `{ "fullSuccess": true, "addedCount": 1, "failedBatchIndex": null }`. Check TIDAL's UI confirms the track is in the playlist.

**Inspector — batching test:**

Repeat with 25 track IDs (any combination from a few `SearchTracks` calls). With `MaxTracksPerBatch = 20`, this is 2 batches with a 500 ms gap. Expect `addedCount: 25`. TIDAL UI confirms 25 tracks (or thereabouts — duplicates allowed if you accidentally repeat IDs).

**Inspector — failure handling test:**

Pick a bad playlist ID (e.g. `"deadbeef"`). Call `AddTracksToPlaylist`. Expect `addedCount: 0, failedBatchIndex: 0`, with an error message containing the underlying 404 or 400. The structured failure is what makes the tool LLM-friendly — Claude can read this and explain to the user what went wrong rather than just surfacing a stack trace.

**claude.ai dev — full flow:**

In a fresh conversation with the "TIDAL Sonics (dev)" connector enabled:

> Build me a 5-song TIDAL playlist called "TIDAL Sonics test" with these tracks:
>  - Radiohead, Pyramid Song
>  - Boards of Canada, Roygbiv
>  - Aphex Twin, Avril 14th
>  - Bonobo, Kong
>  - Burial, Archangel

Expected behavior:

1. Claude calls `find_playlist_by_name("TIDAL Sonics test")` — empty list.
2. Claude calls `create_playlist("TIDAL Sonics test")` — gets new playlist ID.
3. For each of the 5 songs, Claude calls `search_tracks(...)` and surfaces candidates.
4. You confirm the matches (one by one or in a batch).
5. Claude calls `add_tracks_to_playlist(playlistId, [t1, t2, t3, t4, t5])` — single batch since 5 < 20.
6. Claude reports success.

Open TIDAL's app, find the playlist, confirm five tracks present in your confirmed order.

If Claude skips the confirmation step (just picks #1 for each search), the `SearchTracks` description from SPEC-008 needs reinforcement.

**Prod deploy:**

```bash
export IMAGE_TAG=v5
az acr build -r $ACR_NAME -t tidal-sonics-server:$IMAGE_TAG -f Dockerfile .
az containerapp update -g $RG -n $APP_NAME \
  --image $ACR_LOGIN_SERVER/tidal-sonics-server:$IMAGE_TAG
```

(No new Container Apps secrets — the user tokens from SPEC-009 carry over.)

Test the same full-flow prompt through the prod connector.

## Tasks

### Task 1: Verify the add-tracks endpoint shape

Spec 1. Note real path, body shape, and any batch-size guidance from the OpenAPI spec.

### Task 2: Extend config

Spec 2: add `MaxTracksPerBatch` and `InterBatchDelayMs`. Update `TidalOptions`. Commit: `chore: add batching config keys`.

### Task 3: Implement `AddTracksAsync`

Spec 3, with verified path and body from Task 1 substituted. Build. Commit: `feat: add TidalPlaylistClient.AddTracksAsync with batching`.

### Task 4: Add the `AddTracksToPlaylist` tool

Spec 4. Build. Commit: `feat: add add_tracks_to_playlist MCP tool`.

### Task 5: Inspector validation

Spec 5's three Inspector tests (atomic, batching, failure).

### Task 6: claude.ai dev validation — full flow

Spec 5 dev section. The five-track playlist test is the slice's real success criterion: it's the first time the full workflow runs end-to-end in one conversation.

### Task 7: Deploy and prod validation

Spec 5 prod section.

If all of the above pass, SPEC-010 is **Completed**. *The project is now functionally complete for the original use case* — with hardcoded TIDAL tokens. SPEC-011 (Key Vault) and SPEC-012 (automated `/connect-tidal`) are polish.

## Notes

- **The full flow now works end-to-end.** This is the slice where the original goal lands: end a music recommendation chat with "build this as a TIDAL playlist," and the playlist exists. Worth pausing here to use it on a real chat before continuing to the polish specs.
- **Rate-limit tuning.** The 500 ms inter-batch delay is conservative. Once you've watched a few real runs, you can probably drop it to 250 or 100 — TIDAL's write rate-limit may be much looser than catalog reads. Tune it down via config; no code change needed.
- **Partial success in claude.ai.** When `AddTracksResult.FullSuccess == false`, Claude will see the structured result and (with this description) explain to the user that, say, batches 0 and 1 succeeded but batch 2 failed at `<error>`. That's better UX than "the call threw an exception" — and it's why we return the structured type rather than throwing.
- **Order preservation.** `IReadOnlyList<string>` preserves the order Claude passes in, and we send batches in order, so tracks should appear in the playlist in the same order the user confirmed them. Worth verifying in Task 6.
- **Duplicate avoidance is conversation state, not server state.** If a single conversation calls `add_tracks_to_playlist` multiple times with overlapping IDs, the playlist gets duplicates. Claude can keep track of "what's already been added in this conversation" if the user asks for dedup — and the tool description tells it to. Server-side dedup would require reading the playlist's current contents first, which is another round trip and another endpoint, and arguably the LLM's job anyway.
- **What's "done" after SPEC-010.** The functional MVP exists. What remains:
  - SPEC-011 moves secrets from user-secrets / Container Apps native secrets into Key Vault. Important for production hygiene, not for functionality.
  - SPEC-012 replaces the manual `tidal-user-bootstrap.sh` with a `/connect-tidal` server route. Important for "set it and forget it" — removes the once-a-day re-bootstrap risk when refresh tokens rotate and we lose the new one on restart. After SPEC-012 + SPEC-011, the system is fully self-contained.
- **Where to declare victory.** Worth being honest with yourself: if SPEC-010 works for your actual use case and the once-in-a-while manual re-bootstrap doesn't bother you, you can stop here. SPEC-011 and SPEC-012 are real engineering effort for marginal lifestyle improvement on a personal tool. The right answer depends on how often you'd actually re-bootstrap vs how much you want the cleanliness.
