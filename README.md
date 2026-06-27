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
flutter run
```

## Status

See the build plan / milestones. Currently building **M1 — backend core**.
