# Sitos 🍎

A calorie-tracking app. Core loop: **scan a barcode → get instant nutrition info → log it to a daily diary.**

- **Mobile:** Flutter (Android first, iOS later)
- **Backend:** ASP.NET Core / C# (.NET 10), EF Core + PostgreSQL
- **Auth:** Direct Google Sign-In now (provider-agnostic OIDC validation); Microsoft + Apple
  are config-only additions. Entra External ID remains an option — final call before launch.
- **Hosting:** Azure Container Apps + Azure Database for PostgreSQL + Key Vault

The server brokers calls to public nutrition databases and **caches every food it fetches**,
so the cache grows into a shared food database. Users can add their own foods; later we
cross-validate user-submitted data and share verified entries with everyone.

📋 **Design docs:** [`docs/PRD.md`](docs/PRD.md) (full product) ·
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) (system design — read §9 before parallel work) ·
[`docs/ROADMAP.md`](docs/ROADMAP.md) (priorities) · [`docs/BACKLOG.md`](docs/BACKLOG.md) (epics/stories) ·
[`docs/ANALYTICS.md`](docs/ANALYTICS.md) (event taxonomy — instrument as you build) ·
[`docs/DESIGN_NEEDS.md`](docs/DESIGN_NEEDS.md) (designer handoff brief).
Operational/deploy notes live in [`APP_NOTES.md`](APP_NOTES.md).

## Repository layout

```
app/                       # Flutter app
server/
  Sitos.Api/               # ASP.NET Core API + auth
  Sitos.Core/              # domain models, interfaces
  Sitos.Infrastructure/    # EF Core, food providers (Open Food Facts / USDA)
  Sitos.Tests/             # xUnit tests
infra/                     # Azure Bicep IaC
docker-compose.yml         # local Postgres for dev
.github/workflows/         # CI/CD
```

## Data sources

| Source | Role | Auth |
|--------|------|------|
| [Open Food Facts](https://world.openfoodfacts.org/data) | Primary (3.5M+ products, global) | None |
| [USDA FoodData Central](https://fdc.nal.usda.gov/api-guide.html) | Fallback (whole/unbranded foods) | Free API key |

Future: Nutritionix, Edamam, Spoonacular, Open Beauty Facts.

## Local development

### Prerequisites
- .NET 10 SDK · Flutter SDK + Android toolchain · Docker · Git

### 1. Start Postgres
```bash
docker compose up -d
```

### 2. Run the API
```bash
cd server/Sitos.Api
dotnet user-secrets set "Usda:ApiKey" "<your-key>"   # optional fallback
dotnet run
```
Swagger UI: https://localhost:7000/swagger

### 3. Run the app
```bash
cd app
flutter pub get
# The app has two Android flavors (staging/prod) that install side-by-side:
#   net.tinypocket.sitos.staging  ("Sitos (Staging)")  and  net.tinypocket.sitos
flutter run --flavor staging      # emulator → API at 10.0.2.2:5000 by default
# Physical device (same Wi-Fi): point the app at your machine's LAN IP:
flutter run --flavor staging --dart-define=SITOS_API_BASE=http://<your-LAN-ip>:5000
# Against a deployed environment:
flutter build apk --flavor staging --dart-define=SITOS_API_BASE=https://sitos-staging-api.<region>.azurecontainerapps.io
```
A `--flavor` is required now that flavors exist. Run the API bound to all interfaces
so devices can reach it: `dotnet run --urls http://0.0.0.0:5000`.

> **Dev note:** the Android manifest sets `usesCleartextTraffic="true"` so the app can
> talk to the local HTTP API. Production uses the HTTPS Container Apps ingress; tighten
> or remove this flag (or scope it to a debug manifest) before release.

## Deployment (Azure)

Infrastructure as code lives in `infra/main.bicep` (Container Apps + PostgreSQL Flexible
Server + Key Vault + ACR). **Staging and prod are separate, isolated stacks** — same
template, one `environment` parameter — within a single subscription (no separate Azure
account needed). Resources are named `sitos-<env>-*` and tagged with the environment;
staging scales to zero, prod keeps one warm replica.

Provision an environment (staging shown; swap `staging`→`prod`):
```bash
az group create -n sitos-staging -l eastus
az deployment group create -g sitos-staging -f infra/main.bicep \
  -p @infra/main.staging.parameters.json -p pgAdminPassword=<secure-pw>
# first image push + deploy:
ACR=$(az acr list -g sitos-staging --query "[0].name" -o tsv)
az acr build -r "$ACR" -t sitos-api:latest -f server/Dockerfile server
az containerapp update -n sitos-staging-api -g sitos-staging \
  --image "$ACR.azurecr.io/sitos-api:latest"
```

CI builds/tests on every push (`.github/workflows/ci.yml`). `deploy.yml` is a manual
(`workflow_dispatch`) deploy with an **environment** choice (staging/prod) and image tag;
it discovers the env's resource group/ACR automatically and only needs the
`AZURE_CREDENTIALS` secret. Typical flow: deploy to staging → smoke-test on the Play
internal track → re-run for prod with the same tag.

## Status

- ✅ **M0** tooling, monorepo, Docker Postgres
- ✅ **M1** backend core — barcode cache (Open Food Facts/USDA), diary, goals, tests
- ✅ **M2** auth — provider-agnostic OIDC validation + direct Google Sign-In (config-gated;
  falls back to dev user locally); test-auth bypass for automated emulator testing
- ✅ **M3** Flutter app — scan, search, food detail, diary, meals, macros, goals, recipes
- ✅ **M4** Azure **staging** deploy live (Container Apps + Postgres + Key Vault)

For where this is headed — vision, priorities, and the work backlog — see
[`docs/ROADMAP.md`](docs/ROADMAP.md) and [`docs/BACKLOG.md`](docs/BACKLOG.md).
**Next P0s:** natural-language ingredient entry, production deploy, and the auth decision.
