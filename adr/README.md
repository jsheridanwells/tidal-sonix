# Architecture decision records

One ADR per spec, same number. Status is `Proposed` until the spec is worked; flip to `Accepted` when the spec completes,
or `Superseded` with a pointer if a later decision replaces it. Write a new ADR (next free number) when a decision changes
mid-project instead of editing history.

| ADR | Title | Spec | Reference blocks |
|---|---|---|---|
| [ADR-001](ADR-001.md) | Project scaffold and first MCP tool, local only | [SPEC-001](../specs/SPEC-001.md) | 2 |
| [ADR-002](ADR-002.md) | Containerize the server and validate locally | [SPEC-002](../specs/SPEC-002.md) | 4 |
| [ADR-003](ADR-003.md) | Push to ACR, deploy to Container Apps | [SPEC-003](../specs/SPEC-003.md) | 0 |
| [ADR-004](ADR-004.md) | Register the MCP server as a claude.ai custom connector | [SPEC-004](../specs/SPEC-004.md) | 0 |
| [ADR-005](ADR-005.md) | Local dev iteration via dev tunnels | [SPEC-005](../specs/SPEC-005.md) | 1 |
| [ADR-006](ADR-006.md) | Google sign-in via OIDC federation | [SPEC-006](../specs/SPEC-006.md) | 3 |
| [ADR-007](ADR-007.md) | OAuth Authorization Server and JWT-protected MCP endpoint | [SPEC-007](../specs/SPEC-007.md) | 15 |
| [ADR-008](ADR-008.md) | `search_tracks` tool against TIDAL Catalog v2 | [SPEC-008](../specs/SPEC-008.md) | 7 |
| [ADR-009](ADR-009.md) | `find_playlist_by_name` and `create_playlist` tools | [SPEC-009](../specs/SPEC-009.md) | 9 |
| [ADR-010](ADR-010.md) | `add_tracks_to_playlist` tool | [SPEC-010](../specs/SPEC-010.md) | 5 |
| [ADR-011](ADR-011.md) | Migrate secrets to Azure Key Vault | [SPEC-011](../specs/SPEC-011.md) | 4 |
| [ADR-012](ADR-012.md) | `/connect-tidal` bootstrap route | [SPEC-012](../specs/SPEC-012.md) | 9 |
