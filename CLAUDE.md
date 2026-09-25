# TidalSonics — working agreement for Claude Code

Personal MCP server that builds TIDAL playlists from music-discovery chats with Claude. .NET 10, ASP.NET Core minimal API, `ModelContextProtocol.AspNetCore`, Azure Container Apps, OAuth 2.1. Single user (Jeremy).

**Comprehension is the deliverable; working code is second.** Jeremy is rebuilding this project from scratch specifically to understand every part. Optimize for him understanding what was built, not for finishing the task fastest. Never reframe his preferences; check in at decision points; one question at a time.

## Repository layout

| Path | What it is | Read it? |
|---|---|---|
| `specs/SPEC-NNN.md` | One slice each: success criteria, shapes, numbered tasks. Intent, not implementation. | Yes — the task you are working, plus its `depends_on` if needed |
| `adr/ADR-NNN.md` | Decisions and rationale for the same-numbered spec. | Yes — always, before the first task of a spec |
| `reference/SPEC-NNN.md` | Code blocks extracted from the original specs. Hypotheses, not answers. | **No.** See below |
| `src/`, `infra/`, `scripts/` | The actual project, created by working the specs. | Yes |
| `http/` | `.http` requests and saved real responses for external APIs. | Yes — the ground truth for any external API shape |
| `notes/` | Jeremy's own per-spec notes from `/debrief`. | Only when he points you at one |

### `reference/` is off-limits

You cannot read it: a deny rule, a PreToolUse hook, and `.ignore` block every route. Don't try another way when blocked. If you think the reference would help, say so in one sentence; Jeremy will open it himself and paste the relevant block if he wants a comparison.

Reason: the point of this rebuild is that neither of us transcribes pre-written code.

## How a task is worked

1. Jeremy points you at `specs/SPEC-NNN.md`, Task N. Do that task only. Don't start Task N+1, don't refactor adjacent code, don't "while I'm here."
2. Read `adr/ADR-NNN.md` if this is the first task of the spec in this session.
3. Every task carries a bucket tag Jeremy sets before work starts. Behave accordingly:
   - **[A] Jeremy types it.** You answer questions, explain APIs, review what he wrote. You do not create or edit the file. If asked "how would you write this", answer with the shape (signature, the two or three calls involved, the one gotcha) rather than the finished code.
   - **[B] You draft; Jeremy reads every line.** Write the minimum that satisfies the task. Put explanations of non-obvious lines in your response, not in code comments. Expect to be asked to justify any line, and expect rejection of anything he can't explain back.
   - **[C] You own it.** Throwaway or mechanical: scripts, fixtures, a `.gitignore`. Just do it and report.
   - No tag → treat as [A] and ask which it should be. Default is A, not B.
   - In a navigator session (`--settings .claude/modes/navigator.json`) you have no edit tools at all; that's intentional.
4. **Curl before code.** Before any C# touches an external endpoint (TIDAL, Google, Key Vault), the request exists in `http/<service>.http` and a real response is saved under `http/responses/`. The C# then describes a shape that has been observed. Do not write a client against an endpoint nobody has called. If asked to, say so and propose the `.http` entry instead.
5. **Review mode** ("review this", "check against the spec"): list gaps against the spec's `success_criteria` and the task text. Don't fix them. Don't rewrite. Findings, not patches.
6. **Commit per task.** Jeremy writes the commit message. If asked "does this match the diff?", answer plainly; that check is the point.
7. When a spec's success criteria all pass, Jeremy updates the spec's frontmatter `status` and `last_updated`, and flips the ADR `status` to `Accepted`. Don't do this unprompted.

## Skills

Jeremy invokes these; don't invoke them yourself. `/task`, `/hint`, `/draft`, `/probe`, `/review`, `/explain-back`, `/debrief`. See `WORKFLOW.md` for when each is used. Each skill's instructions override your defaults for that turn.

## Spec frontmatter

`status: ForApproval | Ready | InProgress | Blocked | Completed | Abandoned`. A spec becomes `Ready` when Jeremy has read the ADR and tagged the tasks. Only one spec is `InProgress` at a time.

## Environment facts

- **podman, not docker.** Dockerfiles are unchanged; the CLI is `podman build` / `podman run` / `podman images`.
- **Explicit `az` CLI.** Not `azd`, not Bicep, not Terraform, not `az containerapp up`. One resource per command, flags visible.
- **Secrets:** `dotnet user-secrets` locally, Key Vault in production (SPEC-011). Never in the repo, never in `appsettings.json` values, never echoed into a terminal log or a chat message. Tunnel URL and Container Apps FQDN are treated as secrets too.
- **Ports:** local `3001`, container `8080`, mapping always `-p 3001:8080`. MCP endpoint at `/mcp`.
- **Immutable image tags** (`v1`, `v2`, …). No `:latest`.
- **Naming:** solution `TidalSonics`, project `TidalSonics.Server`, image `tidal-sonics-server`, Azure resources `tidal-sonics-<type>`.

## Things not to do

- Don't write tests unless a spec asks. The project's stance is "tests when there's a reason."
- Don't log full MCP tool inputs; they reach Log Analytics and may contain PII or tokens later.
- Don't summarize the whole spec set or the whole `adr/` folder into context. Load the task, its ADR, and the files it touches.
- Don't claim an external API behaves a certain way without a saved response in `http/responses/` to point at.
