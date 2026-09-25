---
id: SPEC-001
topic: tidal-sonics
kind: spec
date: 2026-09-23
last_updated: 2026-09-23
status: Ready
depends_on: []
supersedes:
superseded_by:
adr: adr/ADR-001.md
reference: reference/SPEC-001.md
context_files: []
success_criteria:
  - Solution and single project compile clean on .NET 10
  - dotnet run` starts an MCP server on a known local port
  - MCP Inspector connects, lists the `hello` tool, and successfully invokes it
  - No container, no Azure, no auth in this slice
---

# SPEC-001: Project scaffold and first MCP tool, local only

## ADR

Decisions and rationale for this slice live in [`adr/ADR-001.md`](../adr/ADR-001.md). Read it before starting; do not restate it here.

## Specs

### Spec 1: Repository and solution layout

```
tidal-sonics/
├── .gitignore                       # standard VS / .NET gitignore
├── README.md                        # one-paragraph project overview
├── CLAUDE.md                        # working agreement for Claude Code
├── adr/                             # decisions, one per spec
├── specs/                           # intent: success criteria, shapes, tasks
├── reference/                       # extracted code — off-limits by default
├── src/
│   └── TidalSonics.Server/
│       ├── TidalSonics.Server.csproj
│       ├── Program.cs
│       ├── appsettings.json
│       └── Tools/
│           └── HelloTool.cs
└── TidalSonics.sln
```

`specs/` is where future SPEC-NNN docs live. Claude Code is pointed at the relevant spec when working a task.

### Spec 2: Project file (`TidalSonics.Server.csproj`)

- SDK: `Microsoft.NET.Sdk.Web`
- `TargetFramework`: `net10.0`
- `Nullable`: enabled
- `ImplicitUsings`: enabled
- PackageReferences:
  - `ModelContextProtocol.AspNetCore` — pick the highest 1.x stable at scaffold time, pin it explicitly in the csproj rather than letting `dotnet add` pick a floating range.

No other packages this slice.

### Spec 3: `Program.cs`

Minimal API host that registers the MCP server, configures stateless streamable HTTP transport, discovers tools from the assembly, and binds to a fixed local port for predictable Inspector connection.

> **Code lives in reference.** C# block 1 of `reference/SPEC-001.md` ("Spec 3: `Program.cs`"). Write it yourself first; open the reference only if stuck.
> Shape: `MapMcp()`

Port 3001 is the convention used in the SDK's getting-started docs and Inspector defaults assume that range. Pin it now; parameterise via configuration in a later slice if we ever need to.

### Spec 4: The `Hello` tool

> **Code lives in reference.** C# block 2 of `reference/SPEC-001.md` ("Spec 4: The `Hello` tool"). Write it yourself first; open the reference only if stuck.
> Shape: `class HelloTool` · `public static string Hello(…)`

Deliberately trivial. Single string in, single string out. Static method on a static class — matches the SDK docs and sidesteps DI considerations for this first slice.

The `[Description]` attributes on both the method and the parameter are load-bearing: those strings are what an LLM client (and the Inspector) will see when deciding whether and how to call the tool. Treat tool descriptions as production code from day one — they're the API surface the model sees.

### Spec 5: Local validation via MCP Inspector

MCP Inspector is the official browser-based debugger for MCP servers. Launched via `npx @modelcontextprotocol/inspector`. It opens a UI where you point it at your server's URL/transport, browse the tool list, and invoke tools interactively.

For this slice:

- Server URL: `http://localhost:3001` (with whatever path `MapMcp()` exposes — see Notes)
- Transport: Streamable HTTP
- Expected tool list: one tool named `Hello`
- Expected invocation: `{ "name": "Jeremy" }` → `"Hello, Jeremy! TidalSonics MCP server is alive."`

This is the success criterion for the slice. No further validation needed.

## Tasks

Tasks are ordered. Each is small enough to run, verify, and commit before moving on. Use these as Claude Code prompts.

### Task 1: Initialize the repo and solution

In an empty `tidal-sonics/` directory:

```bash
git init
dotnet new gitignore
dotnet new sln -n TidalSonics
mkdir -p src specs
dotnet new web -n TidalSonics.Server -o src/TidalSonics.Server -f net10.0
dotnet sln add src/TidalSonics.Server/TidalSonics.Server.csproj
```

Verify `dotnet build` succeeds on the empty web project. Commit: `chore: scaffold solution and project structure`.

### Task 2: Add the MCP SDK package

```bash
cd src/TidalSonics.Server
dotnet add package ModelContextProtocol.AspNetCore
```

Inspect `TidalSonics.Server.csproj` and confirm the version that landed is a 1.x stable release. If `dotnet add` pulled a preview, pin to the latest stable 1.x explicitly in the csproj. Commit: `chore: add ModelContextProtocol.AspNetCore`.

### Task 3: Replace the default `Program.cs`

Replace the generated `Program.cs` with the contents from Spec 3 above. Strip any default sample endpoints that `dotnet new web` produced. Commit: `feat: register MCP server with stateless HTTP transport`.

### Task 4: Add the `Hello` tool

Create `src/TidalSonics.Server/Tools/HelloTool.cs` with the contents from Spec 4 above. Commit: `feat: add Hello tool for MCP wiring validation`.

### Task 5: Build and run

```bash
dotnet build
dotnet run --project src/TidalSonics.Server
```

Expected: server logs show it listening on `http://localhost:3001`. Leave it running.

### Task 6: Launch MCP Inspector and validate

In a separate terminal:

```bash
npx @modelcontextprotocol/inspector
```

In the Inspector UI:

1. Set transport to Streamable HTTP.
2. Set server URL to `http://localhost:3001` plus the MCP path (see Notes — likely `/` or `/mcp`).
3. Connect. No auth.
4. Confirm exactly one tool (`Hello`) appears in the list with the description we wrote.
5. Invoke it with `{ "name": "Jeremy" }`.
6. Confirm the response string comes back as expected.

If all six steps pass, SPEC-001 is **Completed**. Update frontmatter `status` and `last_updated`, and commit the spec file.

### Task 7: Stub the README

A `README.md` at the repo root with: project goal in one or two sentences, pointer to `specs/`, how to run locally. Doesn't need to be polished — placeholder we'll grow into. Commit: `docs: project README stub`.

## Notes

- **MCP endpoint path.** `MapMcp()` registers the MCP endpoints at a default path (likely `/` for the streamable HTTP endpoint). If Inspector can't auto-discover, pin it explicitly with `app.MapMcp("/mcp")` and connect to `http://localhost:3001/mcp`. Worth a one-line check during Task 6.
- **Host header validation.** DNS-rebinding protection (host filtering, restrictive CORS) is a production concern called out in the SDK docs. Not needed for localhost dev. We'll address it in SPEC-003 when the server becomes reachable from the public internet.
- **What `dotnet new web` produces.** The minimal `web` template typically gives you just a `Program.cs` with a single `GET /` endpoint and an `appsettings.json` with logging config. Keep `appsettings.json`, strip the sample endpoint.
- **No tests yet.** Test project is deliberately deferred. If at any point during this slice you find yourself wishing for a test scaffold, that's a signal to insert a SPEC-001.5 before continuing — don't bolt it in mid-slice.
