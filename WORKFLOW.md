# Working with Claude Code on TidalSonics

Two workflows, chosen per task by its bucket tag. Both share the same guardrails and the same session shape. The difference is who holds the keyboard.

## Shared guardrails (always on, `.claude/settings.json`)

These are enforced by Claude Code, not by asking nicely in `CLAUDE.md`:

- **`reference/` is unreachable.** A `Read(reference/**)` deny rule, a PreToolUse hook (`.claude/hooks/guard-reference.sh`) that blocks any Bash/Grep/Glob/Read/Edit call naming `reference/`, and a `.ignore` file so ripgrep-backed search skips it. If you want to compare against the reference, open it yourself and paste the block.
- **You commit.** `git commit` and `git push` are denied.
- **Secrets stay unread.** User-secrets store, `~/.azure`, `dotnet user-secrets list`, and `az keyvault secret show` are denied.
- **Infra commands ask.** Every `az`, `podman push`, and `devtunnel` call prompts. You're meant to type those yourself; the prompt is the reminder.

The hook needs `jq` on your PATH.

**Verify the guardrails once** before SPEC-001, in a fresh session: ask Claude Code to "find where TokenIssuer is defined anywhere in this repo." It exists only in `reference/SPEC-007.md`, so the correct outcome is that it finds nothing or reports being blocked. If it quotes the code, a layer leaked; tell me which tool it used.

## Workflow 1 — Navigator (you drive)

For **[A]** tasks: anything you type yourself. Auth, token handling, tool descriptions, `Program.cs` wiring, anything a consumer will depend on.

```bash
claude --settings .claude/modes/navigator.json
```

The navigator mode removes Edit and Write from Claude's toolset entirely. It can read the repo, run `dotnet build`, curl your local server, read logs, and answer questions. It cannot touch a file. You write code in VS Code in a second window.

Session shape:

1. `/task 007 8` — Claude frames the task in ten lines and asks you one question. Answer it before writing anything.
2. Write the code. When stuck: `/hint 1 …`, then `/hint 2 …`, then `/hint 3 …`. Go up one level at a time. Level 3 is a skeleton with holes; there is no level 4.
3. Ask anything else in plain language: "why does `UseAuthentication` have to come before `MapMcp`?", "build it and tell me what the error means." Use the Microsoft Learn MCP server (setup below) so API answers come from current docs.
4. `/review 007 8` — a forked, read-only reviewer checks your diff against the success criteria with no memory of your conversation.
5. Stage, then `/explain-back <your commit message>`. Fix whatever it catches, then commit.
6. End of session: `/debrief 007`.

Example prompts that work well in this mode:

> I'm about to write the `/token` endpoint. Before I start, what are the three ways a PKCE verification can fail, and which HTTP status and `error` value does each return per the spec?

> Build it. Then explain the first error in terms of what the compiler thinks I meant, not how to fix it.

> I've written `TakeIfValid`. Walk me through what happens if claude.ai retries the same code twice within 60 seconds. Don't suggest changes.

## Workflow 2 — Draft and defend (Claude drives, you examine)

For **[B]** tasks: mechanical but still worth understanding. JSON:API parsing, DTOs, DI registration, `.dockerignore`, config binding, the Key Vault configuration source.

```bash
claude --permission-mode default
```

Default (Manual) mode means every edit shows you a diff and waits. That prompt is the reading gate; don't switch to accept-edits for these sessions.

Session shape:

1. `/task 008 5` to frame it.
2. `/draft 008 5` — Claude plans first and stops. Approve or amend the plan.
3. One file per turn, under ~40 changed lines each. After each file Claude asks you two or three defense questions ("what breaks if line 14 goes?"). Answer them before it continues. A wrong answer is the point: it's the gap in your understanding, found cheaply.
4. `/review`, `/explain-back`, commit, `/debrief`, same as Workflow 1.

For **[C]** tasks (scripts, fixtures, `.gitignore`), just ask directly in either mode's session; no ceremony.

## Before any external API: `/probe`

Every TIDAL, Google, or Key Vault endpoint gets probed before code exists, regardless of workflow:

```
/probe tidal search tracks by free-text query, US catalog
```

Claude writes the request into `http/tidal.http`, labels which parts are documented and which are guesses, and stops. You run it with the VS Code REST Client extension, save the redacted response to `http/responses/`, and tell Claude. It then lists where its belief was wrong. That list is the most valuable thing you'll produce in SPEC-008 through SPEC-010.

## Suggested default per spec

Tag the individual tasks yourself; this is where I'd start.

| Spec | Default | Why |
|---|---|---|
| 001 | Navigator | First contact with the MCP SDK. Small enough to type. |
| 002 | Draft & defend | Dockerfile layering is worth defending line by line, not typing. |
| 003–005 | Navigator | You run the `az` / `devtunnel` commands; Claude explains flags and output. |
| 006 | Navigator | Core auth. The whole point of the project. |
| 007 | Navigator, with Draft for the two metadata endpoints | The AS, `/authorize`, and `/token` are the learning; the `.well-known` JSON shapes are not. |
| 008 | `/probe` first, then Draft for parsing, Navigator for the auth handler and tool description | Tool descriptions are the contract the model sees. |
| 009 | Navigator for the token provider, Draft for the client | Token refresh is where the bugs will live. |
| 010 | Draft & defend | Batching logic is mechanical once 009 exists. |
| 011 | Navigator for `az`, Draft for the config source | |
| 012 | Navigator | It's SPEC-006 and SPEC-009 recombined; you should be fast by now. |

## One-time setup

```bash
# jq for the hook (Arch: pacman -S jq; Windows: winget install jqlang.jq)
jq --version

# Microsoft Learn docs as an MCP server, so answers about ASP.NET Core APIs cite current docs
claude mcp add --transport http microsoft-learn https://learn.microsoft.com/api/mcp

# Optional shell aliases
alias ccnav='claude --settings .claude/modes/navigator.json'
alias ccdraft='claude --permission-mode default'
```

Also: VS Code REST Client extension for `http/*.http`, MCP Inspector (`npx @modelcontextprotocol/inspector`), `devtunnel`, `podman`.

## Rules of thumb

- One task per session. `/clear` between tasks; the spec and ADR are the memory, not the chat.
- If Claude says "while I'm here…", the answer is no.
- If you've gone two hints deep and still can't explain the code, stop and write down what you don't understand. That's a better next prompt than "just do it."
- When a spec's assumption turns out wrong, write a new ADR rather than editing the old one. The history of what you believed is part of what you're learning.
