---
id: SPEC-011
topic: tidal-sonics
kind: spec
date: 2026-09-23
last_updated: 2026-09-23
status: Ready
depends_on:
  - SPEC-010
supersedes:
superseded_by:
adr: adr/ADR-011.md
reference: reference/SPEC-011.md
context_files:
  - src/TidalSonics.Server/Program.cs
  - src/TidalSonics.Server/Tidal/TidalUserTokenProvider.cs
success_criteria:
  - An Azure Key Vault exists in the project's resource group; the UAMI has `Key Vault Secrets Officer` on it
  - All production secrets (Google client secret, OAuth signing key, OAuth client credentials, TIDAL client credentials, TIDAL user tokens, allow-list email) live in Key Vault under a documented naming convention
  - The deployed app reads its secrets from Key Vault when the `KEY_VAULT_URI` env var is set; user-secrets continues to work for local dev when it isn't
  - When TIDAL rotates the user refresh token, the new value is persisted back to Key Vault automatically — no manual `dotnet user-secrets set` step required across restarts
  - The previously-set Container Apps native secrets (from SPEC-007/008/009 deploys) are removed; Key Vault is the single production source of truth
  - All existing tools continue to work end-to-end after the migration
---

# SPEC-011: Migrate secrets to Azure Key Vault

## ADR

Decisions and rationale for this slice live in [`adr/ADR-011.md`](../adr/ADR-011.md). Read it before starting; do not restate it here.

## Specs

### Spec 1: Create the Key Vault

```bash
export KV_NAME=kv-tidal-sonics-$RANDOM    # globally unique, 3-24 chars, alphanumeric + dashes
export KV_URI=https://$KV_NAME.vault.azure.net/

az keyvault create \
  -g $RG \
  -n $KV_NAME \
  -l $LOCATION \
  --enable-rbac-authorization true \
  --sku standard

echo "Key Vault: $KV_URI"
```

Capture the `$KV_NAME` (or commit it to your `infra/env.sh`). The vault name is global; pick something memorable but unique.

### Spec 2: Grant RBAC

The UAMI from SPEC-003 needs both read and write on secrets (write is for refresh-token persistence):

```bash
export KV_ID=$(az keyvault show -g $RG -n $KV_NAME --query id -o tsv)

az role assignment create \
  --assignee-object-id $UAMI_PRINCIPAL_ID \
  --assignee-principal-type ServicePrincipal \
  --role "Key Vault Secrets Officer" \
  --scope $KV_ID
```

You also need the role on your own account to set secret values from the CLI:

```bash
export MY_OID=$(az ad signed-in-user show --query id -o tsv)

az role assignment create \
  --assignee-object-id $MY_OID \
  --assignee-principal-type User \
  --role "Key Vault Secrets Officer" \
  --scope $KV_ID
```

### Spec 3: Migrate secrets

Naming convention: every secret name in KV uses the same path as in `IConfiguration`, with `:` replaced by `--`. Set them one-by-one:

```bash
# Google
az keyvault secret set --vault-name $KV_NAME --name "Google--ClientId" --value "$GOOGLE_CLIENT_ID"
az keyvault secret set --vault-name $KV_NAME --name "Google--ClientSecret" --value "$GOOGLE_CLIENT_SECRET"

# Allow-list (note the indexed array syntax)
az keyvault secret set --vault-name $KV_NAME --name "Auth--AllowedEmails--0" --value "$ALLOWED_EMAIL"

# OAuth Authorization Server signing key + claude.ai client
az keyvault secret set --vault-name $KV_NAME --name "OAuth--SigningKeyPem" --file /tmp/signing-key.pem  # if you saved it; otherwise paste --value
az keyvault secret set --vault-name $KV_NAME --name "OAuth--Clients--0--ClientId" --value "claude-ai-prod"
az keyvault secret set --vault-name $KV_NAME --name "OAuth--Clients--0--ClientSecret" --value "$OAUTH_CLIENT_SECRET"
az keyvault secret set --vault-name $KV_NAME --name "OAuth--Clients--0--RedirectUris--0" --value "https://claude.ai/api/mcp/auth_callback"
az keyvault secret set --vault-name $KV_NAME --name "OAuth--Clients--0--RedirectUris--1" --value "https://claude.com/api/mcp/auth_callback"

# TIDAL
az keyvault secret set --vault-name $KV_NAME --name "Tidal--ClientId" --value "$TIDAL_CLIENT_ID"
az keyvault secret set --vault-name $KV_NAME --name "Tidal--ClientSecret" --value "$TIDAL_CLIENT_SECRET"
az keyvault secret set --vault-name $KV_NAME --name "Tidal--UserAccessToken" --value "$TIDAL_USER_ACCESS_TOKEN"
az keyvault secret set --vault-name $KV_NAME --name "Tidal--UserRefreshToken" --value "$TIDAL_USER_REFRESH_TOKEN"
```

For the signing key PEM, the `--file` form is cleaner than escaping newlines in a `--value`. Verify all secrets exist:

```bash
az keyvault secret list --vault-name $KV_NAME --query "[].name" -o table
```

### Spec 4: NuGet packages

```bash
cd src/TidalSonics.Server
dotnet add package Azure.Extensions.AspNetCore.Configuration.Secrets
dotnet add package Azure.Security.KeyVault.Secrets
dotnet add package Azure.Identity
```

- `Azure.Extensions.AspNetCore.Configuration.Secrets` is the config-source bridge (KV → `IConfiguration`).
- `Azure.Security.KeyVault.Secrets` is the SDK for direct read/write (used by `TidalSecretStore`).
- `Azure.Identity` provides `DefaultAzureCredential`.

### Spec 5: Register the Key Vault config source

In `Program.cs`, very early in the builder setup (so subsequent code that reads `IConfiguration` sees KV values):

> **Code lives in reference.** C# block 1 of `reference/SPEC-011.md` ("Spec 5: Register the Key Vault config source"). Write it yourself first; open the reference only if stuck.

The conditional registration is the key bit: local dev sees no env var → block doesn't run → user-secrets stays as the source. Prod gets the env var → KV loads → user-secrets is moot.

### Spec 6: `TidalSecretStore`

Thin wrapper around `SecretClient` for the write-back path:

> **Code lives in reference.** C# block 2 of `reference/SPEC-011.md` ("Spec 6: `TidalSecretStore`"). Write it yourself first; open the reference only if stuck.
> Shape: `interface ITidalSecretStore` · `class KeyVaultTidalSecretStore` · `public Task UpdateRefreshTokenAsync(…)` · `class NoopTidalSecretStore`

Two implementations: the KV-backed one for prod, a no-op for local dev. Registration:

> **Code lives in reference.** C# block 3 of `reference/SPEC-011.md` ("Spec 6: `TidalSecretStore`"). Write it yourself first; open the reference only if stuck.

Local: rotated tokens still emit the warning log from SPEC-009 (you can update user-secrets manually if you want); the write-back is a no-op. Prod: rotation writes back to KV silently.

### Spec 7: Update `TidalUserTokenProvider`

Inject `ITidalSecretStore`. After detecting a rotated refresh token, persist it:

> **Code lives in reference.** C# block 4 of `reference/SPEC-011.md` ("Spec 7: Update `TidalUserTokenProvider`"). Write it yourself first; open the reference only if stuck.
> Shape: `class TidalUserTokenProvider`

Failure to write back is logged as an error but doesn't fail the token request — we already have a working access token, and the next process restart can recover (in the worst case via re-bootstrap).

### Spec 8: Deploy

Update the Container App to set the `KEY_VAULT_URI` env var, and remove the existing native secret refs that KV now supersedes:

```bash
export IMAGE_TAG=v6
az acr build -r $ACR_NAME -t tidal-sonics-server:$IMAGE_TAG -f Dockerfile .

az containerapp update -g $RG -n $APP_NAME \
  --image $ACR_LOGIN_SERVER/tidal-sonics-server:$IMAGE_TAG \
  --set-env-vars "KEY_VAULT_URI=$KV_URI" \
  --remove-env-vars \
    Tidal__ClientId Tidal__ClientSecret \
    Tidal__UserAccessToken Tidal__UserRefreshToken \
    OAuth__Clients__0__ClientId OAuth__Clients__0__ClientSecret \
    Google__ClientId Google__ClientSecret \
    Auth__AllowedEmails__0
```

(The `--remove-env-vars` flag clears any env vars that previously referenced Container Apps native secrets. Adjust the list to match what you actually set across SPEC-007 through SPEC-009.)

Then remove the native secrets themselves:

```bash
az containerapp secret remove -g $RG -n $APP_NAME \
  --secret-names \
    tidal-client-id tidal-client-secret \
    tidal-user-access-token tidal-user-refresh-token
```

(Again, adjust the secret names to match what was set.)

### Spec 9: Validation

**Local:**

`dotnet run` with `KEY_VAULT_URI` unset. Confirm `Hello`, `SearchTracks`, playlist tools all work via user-secrets values. Logs should NOT show any KV activity.

**Prod (deployed):**

In a new claude.ai conversation through the prod connector:

> Search TIDAL for "burial archangel" and show me the candidates.

If this works, KV reads are functioning end-to-end (the request hits `/mcp` → JWT validated using signing key from KV → tool calls TIDAL using credentials from KV).

**Refresh-token rotation:**

This one requires either patience (wait until your existing access token expires) or contrivance (`az keyvault secret set --name "Tidal--UserAccessToken" --value "garbage"` to force a 401, which forces a refresh). Tail logs during the next playlist tool call:

```bash
az containerapp logs show -g $RG -n $APP_NAME --follow
```

Expect to see `TIDAL rotated the user refresh token; persisting new value.` if TIDAL rotates, and the call should succeed. Verify the KV secret value updated:

```bash
az keyvault secret show --vault-name $KV_NAME --name "Tidal--UserRefreshToken" --query value -o tsv
```

(Compare against what you originally set.)

**Cleanup verification:**

```bash
az containerapp secret list -g $RG -n $APP_NAME -o table
```

Should be empty (or only contain non-migrated items if any exist).

## Tasks

### Task 1: Create the Key Vault

Spec 1 commands. Save `$KV_NAME` to `infra/env.sh`.

### Task 2: RBAC grants

Spec 2. Verify with `az role assignment list --scope $KV_ID -o table`.

### Task 3: Migrate secrets

Spec 3. Iterate through every key currently in user-secrets and currently set as a Container Apps native secret. Verify the full list with `az keyvault secret list`.

### Task 4: Add NuGet packages

Spec 4. Commit: `chore: add Azure Key Vault packages`.

### Task 5: Register KV config source

Spec 5 changes to `Program.cs`. Build. Commit: `feat: load configuration from Key Vault when KEY_VAULT_URI is set`.

### Task 6: Implement `TidalSecretStore`

Spec 6. Commit: `feat: add ITidalSecretStore with KV and no-op implementations`.

### Task 7: Update `TidalUserTokenProvider`

Spec 7. Build. Commit: `feat: persist rotated TIDAL refresh tokens to KV`.

### Task 8: Deploy

Spec 8 commands. Watch `az containerapp logs show --follow` during the deploy to confirm the new revision picks up KV values and doesn't fail to start.

### Task 9: Validate locally and in prod

Spec 9's three validation sections.

### Task 10: Confirm Container Apps native secrets are gone

Spec 9's cleanup verification.

If all of the above pass, SPEC-011 is **Completed**.

## Notes

- **The MVP boundary, in case it bears repeating.** SPEC-010 was the functional finish line. After this slice, the functional behavior is *identical* — the same tools do the same things. The win is operational: one source of truth for prod secrets, rotated refresh tokens persist across restarts. If neither of those is causing you pain, you could skip this slice and the project would still do its job.
- **Why `Secrets Officer` (write) and not just `Secrets User` (read).** Write is needed for refresh-token rotation persistence. The alternative — read-only access, log-warning-only on rotation — leaves the SPEC-009 friction in place forever, which kind of defeats the point of moving to KV in the first place. Officer on a single-tenant single-user vault is a fine trust posture.
- **Local dev unchanged.** This is the load-bearing test. After SPEC-011, `dotnet run` against `localhost:3001` should behave exactly as it did at the end of SPEC-010. If your local dev workflow breaks, the KV-source registration isn't actually conditional — debug the env-var check first.
- **`DefaultAzureCredential` chain.** In Container Apps with a UAMI attached, it picks up the managed identity automatically. Locally, it'd walk through Azure CLI → VS → VS Code creds. We don't exercise the local path because we don't want local laptops touching prod secrets — but if you ever do need it (for one-off debugging), `az login` is enough.
- **Key Vault costs.** Standard tier is roughly $0.03 per 10,000 operations + a small per-secret monthly fee. For this project's traffic, expect cents per month. Premium tier (HSM-backed keys) isn't needed unless you adopt the KV Keys feature for signing.
- **The KV Keys path for the signing key.** The more rigorous architecture stores the RSA private key as a KV Key (not Secret), and `TokenIssuer` calls KV to sign each JWT (the key material never leaves KV). It's a bigger change — `SigningCredentials` becomes asynchronous, JwtBearer validation needs a JWKS endpoint to pull the public key. A worthwhile future slice if/when this ever becomes more than a personal tool.
- **Rotation playbook (manual).** For any secret in KV — if you ever rotate (Google client secret, TIDAL client secret, JWT signing key):
  1. `az keyvault secret set --name <name> --value <new>`
  2. Bounce the Container App (`az containerapp revision restart` or push a no-op image update).
  3. Confirm the new value flows through.
  KV stores all versions, so rollback is `az keyvault secret set` with the previous version's value.
- **The signing-key rotation pitfall.** If you rotate the RSA signing key, all currently-issued JWTs become invalid immediately (since `ValidateIssuerSigningKey` checks the current key only). claude.ai will re-run the OAuth flow on the next call — minor user-visible blip. For a personal tool, fine. For multi-user this'd warrant a JWKS endpoint with `kid`-based key selection and a grace period.
- **Why no separate dev / prod vault.** For a single-developer personal project, two vaults is more overhead than benefit. If this ever needs proper environment isolation, that's another slice.
