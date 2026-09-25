---
id: SPEC-004
topic: tidal-sonics
kind: spec
date: 2026-09-23
last_updated: 2026-09-23
status: Ready
depends_on:
  - SPEC-003
supersedes:
superseded_by:
adr: adr/ADR-004.md
context_files: []
success_criteria:
  - Custom connector added in claude.ai, status reads "Connected"
  - In a fresh conversation with the connector enabled, asking Claude to call the `Hello` tool returns the expected greeting
  - Container Apps logs show the inbound request originating from Anthropic IP space during connect and invocation
  - The connector URL is treated as a secret — not in shared docs, repo, screenshots, or chat history
---

# SPEC-004: Register the MCP server as a claude.ai custom connector

## ADR

Decisions and rationale for this slice live in [`adr/ADR-004.md`](../adr/ADR-004.md). Read it before starting; do not restate it here.

## Specs

### Spec 1: Pre-flight

Before opening claude.ai, confirm three things:

1. **Public URL reachable.** From your laptop:
   ```bash
   curl -i https://$APP_FQDN/mcp
   ```
   Expect a response (even an error response is fine — what matters is that you're hitting the container, not getting a DNS or TLS failure). A `405 Method Not Allowed` on GET is normal for the MCP endpoint, which expects POST.
2. **MCP path matches.** If you didn't pin `app.MapMcp("/mcp")` in SPEC-001, this is the moment to do so. Edit `Program.cs`, rebuild the image (`az acr build`), update the Container App to the new image tag (see Spec 3 of this doc for the update command), and re-verify Inspector works against `https://$APP_FQDN/mcp`.
3. **Plan.** Confirm your claude.ai plan supports the number of connectors you'll have. Free tier allows one custom connector; Pro and Max allow multiple. (Team/Enterprise have an Owner-must-add-first workflow that doesn't apply to a personal account.)

### Spec 2: Add the custom connector

In claude.ai:

1. Click your profile icon → **Settings**.
2. **Connectors** in the sidebar.
3. Scroll to the bottom, click **Add custom connector**.
4. Name: `TIDAL Sonics` (or whatever you want shown in the conversation UI).
5. Remote MCP server URL: `https://$APP_FQDN/mcp` (the actual FQDN from SPEC-003).
6. Leave **Advanced settings** untouched. No OAuth Client ID, no Secret.
7. Click **Add**.

claude.ai will attempt the MCP handshake against the URL. On success the connector shows up in your list with a "Connected" indicator. Expect a delay of a few seconds — Container Apps may need to cold-start a replica.

### Spec 3: Updating the deployed image (only if Spec 1 step 2 required a code change)

If you had to change `MapMcp` to pin `/mcp`, redeploy:

```bash
# from repo root, build a new tag
export IMAGE_TAG=v2
az acr build -r $ACR_NAME -t tidal-sonics-server:$IMAGE_TAG -f Dockerfile .

# point the Container App at the new tag
az containerapp update \
  -g $RG \
  -n $APP_NAME \
  --image $ACR_LOGIN_SERVER/tidal-sonics-server:$IMAGE_TAG
```

`update` triggers a new revision; old revisions are kept around so you can roll back via `az containerapp revision activate` if needed. For our usage this is invisible — the FQDN routes to the active revision.

### Spec 4: Enable in a conversation and invoke

1. Start a **new** conversation (don't reuse one without the connector enabled).
2. Click the **+** button on the lower-left of the chat input → **Connectors**.
3. Toggle **TIDAL Sonics** on.
4. Send a prompt like:
   > Use the TIDAL Sonics connector to call the Hello tool with name "Jeremy". Tell me exactly what it returned.

Expected: Claude calls the tool, the tool result appears in the conversation (sometimes collapsed under a tool-call indicator), and Claude's reply quotes the greeting string. Success.

### Spec 5: Watch the logs

In a terminal, before adding the connector or invoking:

```bash
az containerapp logs show -g $RG -n $APP_NAME --follow
```

On connect: expect an inbound request to `/mcp`. On tool invocation: expect a POST to `/mcp` and a corresponding log line from `Microsoft.AspNetCore.Hosting.Diagnostics`. The source IP is Anthropic's cloud, not yours — useful confirmation that the path from Anthropic → Azure is what's working.

### Spec 6: Troubleshooting tree

If the connector adds but shows "Disconnected" or "Error":

| Symptom | Likely cause | First thing to try |
|---|---|---|
| TLS / certificate error | URL has wrong host, or `http://` not `https://` | Re-check the FQDN; Container Apps is always HTTPS |
| 404 on connect | MCP path mismatch | Try with and without `/mcp`; confirm `app.MapMcp(...)` argument matches |
| 5xx during handshake | Server crashing on protocol negotiation | Check Container Apps logs; usually a missing/misconfigured MCP package or transport setting |
| Replica running, no inbound traffic visible | claude.ai not reaching the server | Confirm the FQDN resolves publicly; consider IP allowlist or firewall issues (none should be present in this slice) |
| Cold-start timeout | First request taking too long | Hit `curl https://$APP_FQDN/mcp` once to warm a replica, then retry the connector add |

If the connector connects but tool invocation fails:

- Confirm Claude actually called the tool by expanding the tool-call panel in the conversation. If Claude refused or guessed an answer instead, refine the prompt: "Use the Hello tool from TIDAL Sonics. Pass name=Jeremy."
- Check logs for the inbound request. If it never arrives, the connector toggle in the conversation isn't actually on.

## Tasks

### Task 1: Pre-flight checks

Run the `curl` from Spec 1 against your `$APP_FQDN/mcp`. Confirm reachability. If `MapMcp` was at the default in SPEC-001, do Spec 3 to pin it to `/mcp`, redeploy, and re-verify Inspector works against the new path. Otherwise skip ahead.

### Task 2: Start log tailing

In a dedicated terminal:

```bash
az containerapp logs show -g $RG -n $APP_NAME --follow
```

Leave this running for Tasks 3 and 4 so you can watch handshake and invocation traffic in real time.

### Task 3: Add the custom connector in claude.ai

Walk through Spec 2. Confirm "Connected" status. If it fails, work through the troubleshooting tree in Spec 6 before moving on.

### Task 4: Invoke `Hello` from a fresh conversation

Walk through Spec 4. Capture the conversation URL and Claude's response (text only — don't share the URL). Confirm the corresponding log lines appeared in your tail.

### Task 5: Note the connector URL handling

Add a one-line `secrets.md` (gitignored) to the repo or your password manager noting the connector URL and the conversation you tested it from. Reason: when SPEC-006 lands and we add OAuth, this URL won't change, but the connector will need to be removed-and-re-added (claude.ai doesn't support editing custom connectors in-place — only remove-and-recreate). Having the URL handy saves a trip back into Azure.

If all of the above pass, SPEC-004 is **Completed**. Update frontmatter and commit.

## Notes

- **Removing/editing a custom connector.** claude.ai doesn't support editing a custom connector in place. To change the URL, OAuth config, or name, you remove and re-add. This becomes relevant in SPEC-006.
- **IP allowlisting as defense-in-depth.** Anthropic publishes the IP ranges its connectors call from (search "Anthropic IP addresses" in the support center for the current list). Container Apps supports IP restrictions at the ingress level (`az containerapp ingress access-restriction set`). This would close the gap created by "URL is the only secret" without waiting for SPEC-006. Optional — flagged here for visibility, not part of this slice's tasks.
- **DNS rebinding / host filtering.** The aspnet base image doesn't validate the `Host` header by default. For a server-to-server connector flow this is low risk (no browser involved). Worth knowing about for completeness; not worth blocking on.
- **Plan note.** Free plan supports a single custom connector. You almost certainly have Pro or Max, but if you ever hit a "you can only have one custom connector on this plan" message, that's why.
- **Don't reuse a conversation that pre-dates the connector.** Toggling a connector on in an existing conversation can be flaky in some clients. New conversation removes that variable.
- **Anthropic IPs in logs.** When you see the inbound IPs in Container Apps logs, they'll be from Anthropic's published ranges, not your laptop. This is the cleanest visual confirmation that the Anthropic → Azure path is the one in play.
