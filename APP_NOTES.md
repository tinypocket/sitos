# Sitos — App Notes

Operational notes for building, running, and deploying Sitos. (No secrets in this file.)

## Deployed environments

| Env | Resource group | Region | API URL |
|-----|----------------|--------|---------|
| **staging** | `sitos-staging` | `westus3` | `https://sitos-staging-api.blackwave-889cf415.westus3.azurecontainerapps.io` |
| prod | `sitos-prod` | — | not deployed yet (re-run with `infra/main.prod.parameters.json`) |

Subscription: **Azure subscription 1** (`2758e5fd-…`), tenant `nicktinypocket.onmicrosoft.com`.
Each environment is an isolated stack: Container App + Azure PostgreSQL Flexible Server +
Key Vault + ACR + Log Analytics. Staging scales to zero (cold-starts on first request).

## Azure CLI on this machine

The Azure CLI isn't on the Git Bash PATH; call it by full path:
```
"/c/Program Files/Microsoft SDKs/Azure/CLI2/wbin/az.cmd" <args>
```
(In PowerShell: `& "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd" <args>`.)

## New-subscription restrictions hit (and workarounds)

1. **Postgres `LocationIsOfferRestricted` in westus2** — this subscription can't provision
   PostgreSQL Flexible Server in West US 2. Use **westus3** (or request a quota increase).
2. **ACR Tasks blocked** (`TasksOperationsNotAllowed`) — `az acr build` (server-side build)
   is not permitted. Build the image **locally** and push instead (below). The CI
   `deploy.yml` uses `az acr build`, so either request ACR Tasks access or switch that step
   to local-build-and-push before relying on the workflow.
3. **Docker BuildKit fails** here (buildx container can't start — cgroup/runtime error).
   Build with the **classic builder**: set `DOCKER_BUILDKIT=0`.

## Build & deploy the API image (manual)

```bash
ACR=$(az acr list -g sitos-staging --query "[0].name" -o tsv)
az acr login --name "$ACR"
DOCKER_BUILDKIT=0 docker build -t "$ACR.azurecr.io/sitos-api:latest" -f server/Dockerfile server
docker push "$ACR.azurecr.io/sitos-api:latest"
az containerapp update -n sitos-staging-api -g sitos-staging \
  --image "$ACR.azurecr.io/sitos-api:latest"
```
The API applies EF Core migrations against Postgres on startup, so no manual DB step.

## Provision an environment from scratch

```bash
az group create -n sitos-staging -l westus3
az deployment group create -g sitos-staging -n sitos-staging-deploy \
  -f infra/main.bicep -p @infra/main.staging.parameters.json \
  -p pgAdminPassword=<secure-pw>
# then build & push the image (above) and `az containerapp update`.
```
Required resource providers (register once per subscription): `Microsoft.App`,
`Microsoft.OperationalInsights`, `Microsoft.ContainerRegistry`,
`Microsoft.DBforPostgreSQL`, `Microsoft.KeyVault`.

## Postgres admin password

A strong password was generated at deploy time and is wired into the Container App as a
secret — **the app does not need you to know it**. It is NOT stored in this repo or Key
Vault. If you need direct DB access, reset it to a value you control:
```bash
PG=$(az postgres flexible-server list -g sitos-staging --query "[0].name" -o tsv)
az postgres flexible-server update -g sitos-staging -n "$PG" --admin-password <your-pw>
```

## Run the app

Two Android flavors install side-by-side: `net.tinypocket.sitos.staging`
("Sitos (Staging)") and `net.tinypocket.sitos` ("Sitos"). A `--flavor` is required.

```bash
# Local API (emulator reaches host at 10.0.2.2):
flutter run --flavor staging
# Against deployed staging:
flutter build apk --flavor staging \
  --dart-define=SITOS_API_BASE=https://sitos-staging-api.blackwave-889cf415.westus3.azurecontainerapps.io
```
Run the local API on all interfaces so devices can reach it: `dotnet run --urls http://0.0.0.0:5000`.

## Smoke test a deployed API

```bash
BASE=https://sitos-staging-api.blackwave-889cf415.westus3.azurecontainerapps.io
curl "$BASE/health"
curl "$BASE/api/foods/barcode/3017620422003"   # Nutella → 539 kcal/100g
```

## Outstanding

- **Auth (M2)**: stand up an Entra External ID tenant + Google identity provider + app
  registrations, then set the Container App env vars `EntraExternalId__Authority` and
  `EntraExternalId__Audience` (auth is config-gated; empty = dev-user fallback).
- **prod**: re-run the provision/deploy steps with `infra/main.prod.parameters.json` into a
  `sitos-prod` resource group.
- **CI deploy**: `deploy.yml` assumes `az acr build` works — adjust for the ACR Tasks
  restriction (local build/push) or request access.
