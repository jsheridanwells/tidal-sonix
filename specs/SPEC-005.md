---
id: SPEC-005
topic: tidal-sonics
kind: spec
date: 2026-09-23
last_updated: 2026-09-23
status: Ready
depends_on:
  - SPEC-004
supersedes:
superseded_by:
adr: adr/ADR-005.md
reference: reference/SPEC-005.md
context_files:
  - src/TidalSonics.Server/Properties/launchSettings.json
success_criteria:
  - devtunnel` CLI installed and authenticated to your Microsoft / GitHub account
  - A persistent named tunnel exists with a stable URL and anonymous access enabled on port 3001
  - With `dotnet run` going locally on port 3001 and `devtunnel host` running, `curl https://<tunnel-id>-3001.<region>.devtunnels.ms/mcp` reaches the local server
  - A second claude.ai custom connector ("TIDAL Sonics (dev)") points at the tunnel URL and successfully invokes the `hello` tool (note: MCP .NET SDK registers tool names lowercase — method `Hello` → tool `hello`)
  - Documented start-of-day commands in the repo so this is a one-line workflow going forward
---

# SPEC-005: Local dev iteration via dev tunnels

## ADR

Decisions and rationale for this slice live in [`adr/ADR-005.md`](../adr/ADR-005.md). Read it before starting; do not restate it here.

## Specs

### Spec 1: Install the `devtunnel` CLI

Platform-specific install. Pick one:

```bash
# Windows
winget install Microsoft.devtunnel

# macOS
brew install --cask devtunnel

# Linux
wget https://aka.ms/TunnelsCliDownload/linux-x64 -O devtunnel
chmod +x devtunnel
sudo mv devtunnel /usr/local/bin/
```

Verify with `devtunnel --version`.

### Spec 2: Authenticate

```bash
devtunnel user login
```

Pops a browser. Sign in with Microsoft, Entra ID, or GitHub. Token is cached in the system keychain for several days.

### Spec 3: Create the persistent tunnel

```bash
# Pick a tunnel ID — globally unique, alphanumeric + dashes, short and memorable.
# It appears in the public hostname, so something like `tidal-sonics-jeremy`
# works; add a personal suffix if your first try is taken.
export TUNNEL_ID=tidal-sonics-jeremy

devtunnel create $TUNNEL_ID --allow-anonymous

devtunnel port create $TUNNEL_ID --port-number 3001 --protocol http

devtunnel access create $TUNNEL_ID --port 3001 --anonymous
```

Three commands, in order:

1. **`create --allow-anonymous`** — creates the tunnel with anonymous access permitted at the tunnel level.
2. **`port create --protocol http`** — registers port 3001 with the local protocol set to `http` (our local server speaks HTTP; the public tunnel URL is always HTTPS regardless).
3. **`access create --port 3001 --anonymous`** — explicitly permits anonymous access on that port. The tunnel-level `--allow-anonymous` flag from step 1 sets the policy; this step applies it to the specific port.

The first command prints the tunnel's public hostname pattern. Once a port is registered, the URL for port 3001 will be:

```
https://<TUNNEL_ID>-3001.<region>.devtunnels.ms/
```

…where `<region>` is auto-assigned (usually `usw2`, `use`, `euw`, etc., based on your nearest datacenter). Capture this URL — it's what goes into claude.ai.

### Spec 4: Start hosting

```bash
devtunnel host $TUNNEL_ID
```

Output looks like:

```
Hosting port 3001 at https://tidal-sonics-jeremy-3001.usw2.devtunnels.ms/
   and inspect it at https://tidal-sonics-jeremy-3001-inspect.usw2.devtunnels.ms/
Ready to accept connections for tunnel: tidal-sonics-jeremy
```

The inspection URL is a free network-traffic inspector — useful for seeing exactly what claude.ai is POSTing during handshake.

This process needs to be running while you want the tunnel live. `Ctrl+C` stops hosting; the tunnel definition stays around (it's persistent), so re-running `devtunnel host $TUNNEL_ID` resumes with the same URL.

### Spec 5: Inner-loop workflow

For tool-logic iteration without claude.ai involved:

```bash
# Terminal 1: run the server with auto-reload on save
cd src/TidalSonics.Server
dotnet watch run

# Terminal 2: Inspector
npx @modelcontextprotocol/inspector
```

Connect Inspector to `http://localhost:3001/mcp` over Streamable HTTP. Edit code; `dotnet watch` rebuilds; Inspector reconnects automatically (or click reconnect). This is the fastest path; use it for everything except claude.ai-specific behavior.

### Spec 6: Outer-loop workflow

For claude.ai-specific testing (how Claude phrases tool requests, how it handles ambiguous matches, how the conversation feels):

```bash
# Terminal 1: server
cd src/TidalSonics.Server
dotnet watch run

# Terminal 2: tunnel
devtunnel host $TUNNEL_ID
```

In claude.ai: start a new conversation, toggle on **TIDAL Sonics (dev)** (the connector pointing at the tunnel URL), interact normally.

When `dotnet watch` rebuilds and restarts the local server, claude.ai's connector will reconnect on the next tool call. There might be a one-call lag while it recovers; that's it.

### Spec 7: Register the second claude.ai connector

Same flow as SPEC-004:

1. claude.ai → Settings → Connectors → **Add custom connector**
2. Name: `TIDAL Sonics (dev)`
3. URL: `https://<TUNNEL_ID>-3001.<region>.devtunnels.ms/mcp`
4. Advanced settings: blank (no OAuth)
5. **Add**

You now have two connectors registered. Toggle whichever fits the conversation: prod for "verify against real deploy," dev for "rapid iteration."

### Spec 8: Repo-level workflow doc

Add `scripts/dev.md` (or similar) with the start-of-day commands so this isn't tribal knowledge:

> **Code lives in reference.** Markdown doc block 1 of `reference/SPEC-005.md` ("Spec 8: Repo-level workflow doc"). Write it yourself first; open the reference only if stuck.

(Replace placeholders with your actual tunnel ID and region. **Don't commit this file with the real URL** — gitignore it or keep the placeholder values. The URL is a secret.)

## Tasks

### Task 1: Install and authenticate

Spec 1 + Spec 2. Confirm `devtunnel user show` returns your identity.

### Task 2: Create the persistent tunnel

Run the three commands in Spec 3. Save the resulting URL somewhere private (password manager or gitignored file). Verify with:

```bash
devtunnel show $TUNNEL_ID
```

### Task 3: Validate the tunnel with a simple service

Quickest sanity check before involving the MCP server. In one terminal, host the tunnel:

```bash
devtunnel host $TUNNEL_ID
```

In another, start a trivial local server on 3001:

```bash
devtunnel echo http -p 3001
```

(`devtunnel echo` is a built-in echo server for exactly this purpose.) Then curl the tunnel URL from a third terminal:

```bash
curl https://<TUNNEL_ID>-3001.<region>.devtunnels.ms/
```

Confirm a response. Stop the echo server and the tunnel host. This validates the tunnel plumbing independently of the MCP server.

### Task 4: Run the real MCP server through the tunnel

```bash
# Terminal 1
cd src/TidalSonics.Server && dotnet watch run

# Terminal 2
devtunnel host $TUNNEL_ID

# Terminal 3
curl -i -X POST https://<TUNNEL_ID>-3001.<region>.devtunnels.ms/mcp
```

Any non-network-error response from the server (even a 4xx from the MCP endpoint) means the path is open. Then point MCP Inspector at the tunnel URL (rather than localhost) over Streamable HTTP and confirm it lists `Hello` and can invoke it through the tunnel.

### Task 5: Add the dev connector in claude.ai

Walk through Spec 7. Confirm "Connected" status.

### Task 6: End-to-end validation via conversation

In a new claude.ai conversation, enable **TIDAL Sonics (dev)** (and disable "TIDAL Sonics" prod if it's on), then:

> Use the Hello tool from TIDAL Sonics (dev). Pass name "Jeremy".

Confirm Claude calls the tool and the response surfaces. Then change the greeting string in `HelloTool.cs`, save the file, wait for `dotnet watch` to restart, and ask Claude to call it again. The new string should come back — proving the iteration loop is live.

### Task 7: Document the workflow

Create `scripts/dev.md` (or wherever you'd naturally look for it). Use the template in Spec 8. Make sure it's either gitignored or has the real URL stripped before commit.

If all of the above pass, SPEC-005 is **Completed**.

## Notes

- **Anti-phishing interstitial.** Dev tunnels show a one-time anti-phishing page on first browser visit to a tunnel URL. This is GET-only / browser-only and won't affect claude.ai's POST-based MCP traffic. If you ever see weird connection failures and want to rule it out, add the header `X-Tunnel-Skip-AntiPhishing-Page: True` to manual curl commands.
- **30-day inactivity expiration.** Tunnels auto-delete after 30 days of no use. Extend with `devtunnel update $TUNNEL_ID --expiration 30d` periodically or whenever you remember. If a tunnel expires and you have to re-create it under the same name, the URL stays the same — but if the name's been taken in the interim you'll have to pick a new one and update the claude.ai connector.
- **The inspection URL.** `https://<TUNNEL_ID>-3001-inspect.<region>.devtunnels.ms` shows request/response traffic through the tunnel in a DevTools-like UI. Genuinely useful for seeing what claude.ai is sending during handshake — recommended when you hit unexpected behavior.
- **Cost.** Free for personal use within the documented limits (10 tunnels, 5 GB bandwidth on Enterprise plans; lower limits are not published for free use but easily covered by personal-tool traffic).
- **`dotnet watch` and connector reconnects.** When `dotnet watch` rebuilds, the server briefly drops connections. The claude.ai connector will mark itself "Disconnected" momentarily and recover on the next tool call. Don't be alarmed by red badges that recover within a few seconds.
- **Host header rewriting.** Dev tunnels rewrites the `Host` header to `localhost:<port>` by default before forwarding to the local server. Fine for plain MCP calls. When SPEC-006 adds OAuth, the OAuth callback flow may need the original tunnel hostname preserved — `devtunnel access` has flags for that, addressed there.
- **Two connectors visible in conversations.** With prod and dev both registered, it's worth a quick sanity check before each session that you've toggled the right one. claude.ai shows the connector name in the tool-call panel; glance at it before assuming a call hit production.
