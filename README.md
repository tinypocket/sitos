# Sitos 🍎

A calorie-tracking app. Core loop: **scan a barcode → get instant nutrition info → log it to a daily diary.**

- **Mobile:** Flutter (Android first, iOS later)
- **Backend:** ASP.NET Core / C# (.NET 10), EF Core + PostgreSQL
- **Auth:** Microsoft Entra External ID (Google → Microsoft → Apple)
- **Hosting:** Azure Container Apps + Azure Database for PostgreSQL + Key Vault

The server brokers calls to public nutrition databases and **caches every food it fetches**,
so the cache grows into a shared food database. Users can add their own foods; later we
cross-validate user-submitted data and share verified entries with everyone.

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
flutter run                                   # on an Android emulator: reaches the API at 10.0.2.2:5000
# Physical device (same Wi-Fi): point the app at your machine's LAN IP:
flutter run --dart-define=SITOS_API_BASE=http://<your-LAN-ip>:5000
```
Run the API bound to all interfaces so devices can reach it:
`dotnet run --urls http://0.0.0.0:5000`.

> **Dev note:** the Android manifest sets `usesCleartextTraffic="true"` so the app can
> talk to the local HTTP API. Production uses the HTTPS Container Apps ingress; tighten
> or remove this flag (or scope it to a debug manifest) before release.

## Deployment (Azure)

Infrastructure as code lives in `infra/main.bicep` (Container Apps + PostgreSQL Flexible
Server + Key Vault + ACR). Outline:
```bash
az group create -n sitos-rg -l eastus
az deployment group create -g sitos-rg -f infra/main.bicep -p @infra/main.parameters.json
az acr build -r <acr> -t sitos-api:latest -f server/Dockerfile server
az containerapp update -n sitos-api -g sitos-rg --image <acr>.azurecr.io/sitos-api:latest
```
CI builds/tests on every push (`.github/workflows/ci.yml`); `deploy.yml` is a manual
image-build-and-deploy (needs `AZURE_CREDENTIALS`, `ACR_NAME`, `RESOURCE_GROUP` secrets).

## Status

- ✅ **M0** tooling, monorepo, Docker Postgres
- ✅ **M1** backend core — barcode cache (Open Food Facts/USDA), diary, goals, tests
- ✅ **M2** Entra External ID auth (config-gated; falls back to dev user locally)
- ✅ **M3** Flutter app — scan, food detail, diary, goals
- ⏳ **M4** Azure deploy — IaC + CI/CD authored; first deploy pending Azure subscription

Next: stand up the Entra External ID tenant (enable Google), then deploy to Azure.
