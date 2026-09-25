---
id: SPEC-003
topic: tidal-sonics
kind: spec
date: 2026-09-23
last_updated: 2026-09-23
status: Ready
depends_on:
  - SPEC-002
supersedes:
superseded_by:
adr: adr/ADR-003.md
context_files:
  - Dockerfile
  - .dockerignore
success_criteria:
  - ACR exists in the chosen region, admin user disabled, holds the `tidal-sonics-server:v1` image
  - User-assigned managed identity exists and has the `AcrPull` role on the ACR
  - Container App is running with the managed identity attached, pulling from ACR via that identity
  - Public HTTPS FQDN is reachable; MCP Inspector against it lists and invokes the `Hello` tool
  - Scale-to-zero observed (replicas drop to 0 after idle period)
---

# SPEC-003: Push to ACR, deploy to Container Apps

## ADR

Decisions and rationale for this slice live in [`adr/ADR-003.md`](../adr/ADR-003.md). Read it before starting; do not restate it here.

## Specs

### Spec 1: Prerequisites

- Azure CLI installed and logged in (`az login`); active subscription selected (`az account show`).
- `containerapp` CLI extension installed and current: `az extension add --upgrade -n containerapp`.
- Resource providers registered: `Microsoft.App`, `Microsoft.ContainerRegistry`, `Microsoft.OperationalInsights`. Single command:
  ```bash
  az provider register -n Microsoft.App
  az provider register -n Microsoft.ContainerRegistry
  az provider register -n Microsoft.OperationalInsights
  ```
  Registration is async; usually finishes in under a minute. `az provider show -n Microsoft.App --query registrationState` to check.

### Spec 2: Resource naming

ACR names must be globally unique, alphanumeric only, 5–50 chars. Suggest a short suffix to avoid clashes:

```bash
export LOCATION=eastus2
export RG=tidal-sonics-rg
export ACR_NAME=tidalsonicsacr$RANDOM      # globally unique; ACR names are alphanumeric-only — no hyphens allowed
export ACR_LOGIN_SERVER=$ACR_NAME.azurecr.io
export UAMI_NAME=tidal-sonics-id
export ENV_NAME=tidal-sonics-cae
export APP_NAME=tidal-sonics-ca
export IMAGE_TAG=v1
```

Save this block in `infra/env.sh` or similar so re-deploys re-source it. Don't commit the actual generated `$ACR_NAME` if you randomized it — keep that in a gitignored file. (Or pick a deliberate name and commit it; either is fine for a single-user tool.)

### Spec 3: Create RG, ACR, and managed identity

```bash
az group create -n $RG -l $LOCATION

az acr create \
  -g $RG \
  -n $ACR_NAME \
  --sku Basic \
  --admin-enabled false

az identity create \
  -g $RG \
  -n $UAMI_NAME

export UAMI_ID=$(az identity show -g $RG -n $UAMI_NAME --query id -o tsv)
export UAMI_PRINCIPAL_ID=$(az identity show -g $RG -n $UAMI_NAME --query principalId -o tsv)
export ACR_ID=$(az acr show -g $RG -n $ACR_NAME --query id -o tsv)
```

Grant the UAMI `AcrPull` on the registry:

```bash
az role assignment create \
  --assignee-object-id $UAMI_PRINCIPAL_ID \
  --assignee-principal-type ServicePrincipal \
  --role AcrPull \
  --scope $ACR_ID
```

Using `--assignee-object-id` + `--assignee-principal-type` rather than `--assignee` avoids the AAD lookup latency that sometimes causes role-create to flake when the identity was just made.

### Spec 4: Build and push the image via `az acr build`

From the repo root (where the `Dockerfile` lives):

```bash
az acr build \
  -r $ACR_NAME \
  -t tidal-sonics-server:$IMAGE_TAG \
  -f Dockerfile \
  .
```

ACR uploads the build context (subject to `.dockerignore`), builds remotely on its own workers, and stores the resulting image. Faster than push-from-local for big images, and no local Docker daemon needed.

Verify:

```bash
az acr repository show-tags -n $ACR_NAME --repository tidal-sonics-server -o table
```

Should list `v1`.

### Spec 5: Create the Container Apps environment and app

```bash
az containerapp env create \
  -g $RG \
  -n $ENV_NAME \
  -l $LOCATION
```

(Takes a couple of minutes; env creation provisions a Log Analytics workspace too.)

```bash
az containerapp create \
  -g $RG \
  -n $APP_NAME \
  --environment $ENV_NAME \
  --image $ACR_LOGIN_SERVER/tidal-sonics-server:$IMAGE_TAG \
  --registry-server $ACR_LOGIN_SERVER \
  --registry-identity $UAMI_ID \
  --user-assigned $UAMI_ID \
  --ingress external \
  --target-port 8080 \
  --transport auto \
  --min-replicas 0 \
  --max-replicas 1 \
  --cpu 0.25 \
  --memory 0.5Gi
```

Key flags worth understanding:

- `--registry-identity $UAMI_ID` tells Container Apps to use that managed identity to pull from ACR. Combined with the `AcrPull` role grant from Spec 3, the pull works without registry credentials.
- `--user-assigned $UAMI_ID` attaches the UAMI to the running container so it can use the same identity for outbound calls (Key Vault, etc., later).
- `--transport auto` lets Container Apps pick the best HTTP transport. Streamable HTTP works over HTTP/1.1 and HTTP/2; `auto` handles both. Pin to `http` or `http2` later if needed.

Get the public FQDN:

```bash
export APP_FQDN=$(az containerapp show -g $RG -n $APP_NAME --query properties.configuration.ingress.fqdn -o tsv)
echo "https://$APP_FQDN"
```

### Spec 6: Validation

Public URL test (curl just confirms the container is up at the network level):

```bash
curl -i https://$APP_FQDN/
```

Then point MCP Inspector at `https://$APP_FQDN` (with whatever MCP path you pinned in SPEC-001 — likely `/` or `/mcp`). Streamable HTTP transport. Confirm:

- Tool list shows `Hello`
- Invoking with `{ "name": "Jeremy" }` returns the expected greeting

Then **wait a few minutes without making requests** and watch the replica count:

```bash
az containerapp replica list -g $RG -n $APP_NAME -o table
```

Should drop to zero after the idle threshold (default a few minutes). Next request will cold-start a replica back up — first request after idle takes a couple of seconds, subsequent ones are fast. This is the cost model working as intended.

## Tasks

### Task 1: Prereqs and naming

Run the resource-provider registrations from Spec 1. Source the env-var block from Spec 2 in your shell. Confirm `az account show` is the subscription you want. No commit yet — these are shell setup.

### Task 2: Resource group, ACR, UAMI

Run the four commands in Spec 3 to create the RG, ACR, and UAMI, capture the IDs, and grant `AcrPull`. Sanity-check:

```bash
az acr show -g $RG -n $ACR_NAME --query "{name:name, sku:sku.name, adminUserEnabled:adminUserEnabled}" -o table
az role assignment list --assignee $UAMI_PRINCIPAL_ID --scope $ACR_ID -o table
```

Commit any scripts/notes to `infra/` if you wrote them down.

### Task 3: Build and push the image

Run `az acr build` from Spec 4. Confirm the tag landed via `az acr repository show-tags`.

### Task 4: Container Apps environment

Run the env-create command from Spec 5. Wait for completion.

### Task 5: Container App

Run the `az containerapp create` command from Spec 5. On success, capture and echo `$APP_FQDN`. Confirm replica is running:

```bash
az containerapp replica list -g $RG -n $APP_NAME -o table
```

Should show one replica in `Running` state.

### Task 6: Validate via Inspector against the public URL

Launch Inspector locally, connect to `https://$APP_FQDN` over Streamable HTTP, list tools, invoke `Hello`. Capture the output for the spec's commit message.

### Task 7: Confirm scale-to-zero

Don't make any requests for several minutes. Re-run `az containerapp replica list`. Confirm zero replicas. Then hit Inspector once more; confirm a replica spins up and the call succeeds (with a noticeable cold-start delay on first call).

If all of the above pass, SPEC-003 is **Completed**. Update frontmatter and commit. Add `infra/env.sh` (or whatever you named it) to the repo, gitignored if it contains anything sensitive — though for now it's just resource names.

## Notes

- **Alternative: push from local instead of `az acr build`.** If you'd rather use the image you already built in SPEC-002:
  ```bash
  az acr login --name $ACR_NAME
  docker tag tidal-sonics-server:dev $ACR_LOGIN_SERVER/tidal-sonics-server:$IMAGE_TAG
  docker push $ACR_LOGIN_SERVER/tidal-sonics-server:$IMAGE_TAG
  ```
  Same result. `az acr build` was chosen for the spec because it removes a moving part.
- **Cost estimate for this slice.** ACR Basic flat ~$5/mo. Container Apps with min-replicas 0 and minimal traffic: $0–$1/mo (well within the monthly free grant). Log Analytics workspace from the env: usually <$1/mo at this scale. Total: ~$5–$6/mo, all of which is ACR. The cheaper alternative is using GitHub Container Registry (free for public repos) and configuring Container Apps to pull from it, but that's a different slice and loses some of the Azure-native experience you're optimizing for.
- **Replica cold-starts.** With min-replicas 0, the first request after idle hits a ~2–5 second cold start. Acceptable for an interactive tool you'll trigger a handful of times per session. If it starts feeling sluggish, bump min-replicas to 1 — but that breaks the free-tier math.
- **Logs.** `az containerapp logs show -g $RG -n $APP_NAME --follow` streams stdout/stderr. Useful when something is failing. Note the warning from the .NET MCP guidance: don't log full tool inputs — they end up in Log Analytics and may contain PII or secrets later when we add TIDAL.
- **`MapMcp` path consistency.** Whatever path you pinned in SPEC-001 still applies. The public FQDN doesn't change the routing.
