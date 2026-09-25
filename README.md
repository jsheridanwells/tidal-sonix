# TidalSonics — restart

Rebuild of the TIDAL Sonics MCP server from a clean repo, for learning. Twelve specs, one slice each, worked in order.

## Layout

- `CLAUDE.md` — working agreement for Claude Code.
- `WORKFLOW.md` — the two ways to work a task (Navigator, Draft & defend), the skills, and one-time setup. Read this first.
- `.claude/` — settings with guardrails, the `reference/` guard hook, navigator mode, the reviewer subagent, and the skills.
- `http/` — `.http` requests and saved responses; `notes/` — your per-spec notes.
- `adr/` — one ADR per spec (same number). Decisions and rationale. Read the ADR before working its spec.
- `specs/` — one spec per slice: frontmatter with success criteria, `Specs` (shapes and procedures), `Tasks`, `Notes`. Code has been removed and replaced with a placeholder pointing at `reference/`.
- `reference/` — the code blocks that were removed from the specs, kept for when you're stuck. Blocked for Claude Code by permissions and a hook; off-limits to you until you've written your own attempt.

## What moved to `reference/` and what didn't

Repo files moved: C#, JSON config, Dockerfile, `.dockerignore`, the SPEC-005 dev-workflow doc, the SPEC-009 bootstrap script. Commands you type at a terminal (`az`, `podman`, `dotnet`, `devtunnel`, `curl`, `openssl`) stayed in the specs: there's nothing to transcribe wrongly, and the learning is in reading the flags and the output. Directory trees and example output also stayed.

Each placeholder carries a `Shape:` line auto-extracted from the removed code (types, public methods, routes) so the spec still tells you *what* to build without telling you *how*. The extraction is regex-based; treat it as a hint.

## Before starting a spec

1. Read `adr/ADR-NNN.md`.
2. Tag every task in `specs/SPEC-NNN.md` with `[A]`, `[B]`, or `[C]` (see `CLAUDE.md`). Put it at the front of the task heading, e.g. `### Task 3 [A]: Replace Program.cs`.
3. Set `status: Ready`.

## Not carried over

The previous attempt's handoff document and its discovered facts were deliberately left out. Statuses are reset to `ForApproval`, dates to 2026-09-23. Anything the specs assert about external APIs — TIDAL endpoint paths, batch sizes, rate limits — is unverified until you have a saved response in `http/responses/`.
