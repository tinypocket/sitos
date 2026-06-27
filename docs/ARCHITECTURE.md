# Sitos — System Architecture & Engineering Design

**Audience:** engineers and AI coding agents working on Sitos.
**Purpose:** describe how the system is built *and* how to extend it so that **multiple agents
can work in parallel without colliding**. Read §9 ("Working in parallel") before starting a task.

---

## 1. Architectural goals

1. **Fast, reliable logging loop** — cache-first reads, provider failures never break a request.
2. **Deterministic nutrition** — the database is the source of truth; external calls (providers,
   LLM) are inputs that get normalized and persisted, never trusted blindly.
3. **Swappable seams** — food providers and the identity provider sit behind interfaces.
4. **Parallel-friendly** — clear module boundaries and a contracts-first API so backend and
   mobile work can proceed independently and merge cleanly.
5. **Cheap to operate** — managed Azure services, scale-to-zero staging, cheapest-capable AI.

## 2. System context (C4 level 1)

```
        ┌─────────────┐        HTTPS / JWT        ┌──────────────────────────┐
        │  Flutter app │ ───────────────────────▶ │  Sitos API (ASP.NET Core)│
        │ (Android→iOS)│ ◀─────────────────────── │  Azure Container Apps     │
        └─────────────┘        JSON DTOs          └─────────┬────────────────┘
              │ OIDC                                          │ EF Core
              ▼                                               ▼
        ┌─────────────┐                              ┌──────────────────┐
        │ Google /     │                             │ Azure PostgreSQL │  ← source of truth
        │ Entra (OIDC) │                             └──────────────────┘    (foods cache,
        └─────────────┘                                                       users, diary,
                                                     ┌──────────────────┐     goals, recipes)
                        outbound, cached/persisted ▶ │ Open Food Facts  │
                                                     │ USDA FoodData    │
                                                     │ Claude (parsing) │  ← proposes, never
                                                     └──────────────────┘     the source of truth
```

## 3. Repository layout (the module map)

This map is also the **ownership map** for parallel work — a task names the module(s) it touches.

```
sitos/
  server/                              # ASP.NET Core (.NET 10) — see §4
    Sitos.Core/                        # domain: entities, enums, abstractions, pure math. NO I/O.
      Entities/                        #   Food, User, DiaryEntry, Goal, Recipe, RecipeIngredient
      Abstractions/                    #   IFoodProvider, IFoodService, IRecipeService, IIngredientParser
      Enums.cs  NutritionMath.cs
    Sitos.Infrastructure/              # data + external integrations (depends on Core)
      SitosDbContext.cs  Migrations/   #   EF Core model + migrations
      Providers/                       #   OpenFoodFactsProvider, UsdaProvider (IFoodProvider)
      Services/                        #   FoodService, RecipeService (orchestration + persistence)
    Sitos.Api/                         # HTTP edge (depends on Core + Infrastructure)
      Endpoints/                       #   *Endpoints.cs — one file per feature area (minimal APIs)
      Contracts/                       #   *Dtos.cs — the wire contract (request/response records)
      Auth/                            #   ICurrentUser, OidcCurrentUser, DevCurrentUser, AuthOptions
      Program.cs                       #   composition root (DI + middleware + endpoint mapping)
    Sitos.Tests/                       # xUnit (Core/Infrastructure logic)
  app/                                 # Flutter (Android first, iOS later) — see §5
    lib/
      models.dart                      #   DTO mirrors (fromJson) — the app side of the contract
      api_client.dart                  #   single typed HTTP client (Dio) — all API calls here
      auth_service.dart                #   Google Sign-In + token; gates the app
      providers.dart                   #   Riverpod providers (state)
      screens/                         #   one file per screen (diary, scan, recipe, goal, ...)
      main.dart                        #   app entry + go_router routes + auth gate
  infra/                               # Azure Bicep (Container Apps + Postgres + KV + ACR)
  .github/workflows/                   # CI (build/test) + manual deploy
  docs/                                # PRD.md, ARCHITECTURE.md (this file)
```

**Dependency rule (enforced by project references):** `Core ← Infrastructure ← Api`. Core
depends on nothing. Never reference `Infrastructure`/`Api` types from `Core`.

## 4. Backend design

### 4.1 Layers & responsibilities
- **Core** — entities, enums, and **interfaces only** for behavior, plus pure functions
  (`NutritionMath.ResolveGrams`). No EF, no HTTP, no DI. This is the stable contract every
  other layer codes against, so it's the lowest-collision place to define a new capability.
- **Infrastructure** — `SitosDbContext` (the data model), `IFoodProvider` implementations
  (external food APIs, each with a typed `HttpClient`), and **services** that orchestrate
  cache-first logic and own persistence (`FoodService`, `RecipeService`).
- **Api** — minimal-API endpoint groups, request/response **DTOs** (the wire contract),
  auth wiring, and the composition root. Endpoints are thin: validate input → call a
  service or `DbContext` → map to DTO.

### 4.2 Key patterns (reuse these; don't reinvent)
- **Cache-first resolution** (`FoodService`): check the local `Food` table → on miss, try
  providers **in `FoodSource` priority order** → **persist the hit** → return. Search persists
  provider results too, so every returned food has a stable id usable as a diary/recipe FK.
- **Provider abstraction** (`IFoodProvider`): `FindByBarcodeAsync` / `SearchAsync` return an
  unsaved `Food`; the *service* persists. Add a provider by implementing the interface and
  registering a typed `HttpClient` in `DependencyInjection.cs` — nothing else changes.
- **Provider resilience:** providers catch on `!ct.IsCancellationRequested` (so a timeout
  returns empty, not a 500) and log a warning. **Never let an external call surface as a 500.**
- **Per-user identity** (`ICurrentUser`): endpoints depend only on this. `OidcCurrentUser`
  reads the validated token's `sub`/`oid`, provisions a local `User` on first call, and
  returns the local id. `DevCurrentUser` is the no-auth local fallback. Auth is config-gated:
  set `Auth:Authority`/`Audience` → enforced; unset → dev user.
- **Recipe = backing food** (`RecipeService`): a recipe's per-serving nutrition is materialized
  into a `Food` (`Source = Recipe`, excluded from search/recent) so logging a serving reuses
  the ordinary `DiaryEntry` path — no special-casing downstream.
- **Migrations:** model change in `Core` entity + `SitosDbContext` config → `dotnet-ef
  migrations add <Name>` → committed. The API applies migrations on startup.

### 4.3 Data model (current)
`User(Id, ExternalId, …)` · `Food(Id, Barcode?, Name, per-100g macros, Source, VerifiedStatus,
CreatedByUserId?, RawJson)` · `DiaryEntry(Id, UserId, FoodId, Date, Meal, Quantity, Unit)` ·
`Goal(UserId, DailyCalorieTarget, macro targets?)` · `Recipe(Id, UserId, Name, Servings,
BackingFoodId)` · `RecipeIngredient(Id, RecipeId, FoodId, Quantity, Unit)`.
All nutrition is normalized **per 100 g**; `NutritionMath.ResolveGrams` converts a
quantity+unit (+ optional serving size) to grams identically for diary entries and recipes.

## 5. Mobile design (Flutter)
- **Contract mirror:** `models.dart` holds `fromJson` mirrors of the backend DTOs; `api_client.dart`
  is the *only* place that talks HTTP (Dio). A Bearer-token interceptor attaches the auth token.
- **State:** Riverpod. `apiProvider` (client), `selectedDateProvider`, `diaryProvider`,
  `goalProvider`, `recipesProvider`, `recentFoodsProvider`. Screens watch providers and
  `ref.invalidate(...)` after mutations.
- **Navigation:** `go_router`; the router's `redirect` enforces the auth gate (only when a
  Google client id is configured — otherwise dev mode is open).
- **Config via dart-define:** `SITOS_API_BASE` (API URL), `SITOS_GOOGLE_SERVER_CLIENT_ID`
  (enables the login gate), `SITOS_TEST_TOKEN` (dev/staging test-auth bypass).
- **Flavors:** `staging` / `prod` build flavors install side-by-side with distinct app ids.

## 6. The contract is the seam

The **REST API + DTOs are the single integration boundary** between backend and mobile.
- Backend DTOs: `server/Sitos.Api/Contracts/*Dtos.cs`. Mobile mirrors: `app/lib/models.dart`.
- **Rule:** when you change a DTO, change both sides in the same task, and treat the DTO shape
  as the spec. Endpoints are enumerated in `*Endpoints.cs`; keep them RESTful and per-user.
- Swagger is enabled in dev for the live contract.

Current surface (representative): `GET /api/foods/barcode/{code}`, `GET /api/foods/search`,
`POST /api/foods`, `GET/POST/PUT/DELETE /api/diary`, `GET /api/diary/recent-foods`,
`GET/PUT /api/profile/goal`, `GET /api/me`, `GET/POST/PUT/DELETE /api/recipes`,
`POST /api/recipes/{id}/log`.

## 7. AI integration (natural-language parsing)

The only place an LLM enters Sitos is **parsing free-form ingredient text into structure**.
It is a narrow, swappable, cost-bounded capability — designed so the database stays the source
of truth for all nutrition.

### 7.1 Design
- **Abstraction:** `IIngredientParser` in `Sitos.Core/Abstractions` with
  `Task<IReadOnlyList<ParsedIngredient>> ParseAsync(string text, CancellationToken)`, where
  `ParsedIngredient = (string Name, double? Quantity, string? Unit, string RawText, string? Note)`.
  Pure contract — no SDK types leak into Core.
- **Implementation:** `ClaudeIngredientParser` in `Sitos.Infrastructure` using the official
  **Anthropic C# SDK** (`Anthropic` NuGet, `AnthropicClient`).
  - **Model:** `claude-haiku-4-5` — fastest/cheapest tier, correct for a simple extraction task
    (Opus/Sonnet are overkill here). Model id and API key come from config (`Ai:Anthropic:*`),
    key from Key Vault. Feature is **off unless configured**.
  - **Structured output:** constrain the response with a JSON schema (`output_config.format`,
    `type: json_schema`) so the result is a validated array of ingredient objects — no prose
    parsing. The system prompt states the one job (extract + normalize quantities/units; mark
    unknowns) and is the **cached prefix** (`cache_control: ephemeral`) so repeat calls are cheap.
  - **Resilience/cost:** short timeout; on any failure return empty + log (feature degrades, app
    falls back to manual add). Cost target ≪ \$0.01/parse; usage logged. Only the ingredient
    text is sent — never PII or diary history.
- **Resolution (deterministic, in Infrastructure):** for each `ParsedIngredient`,
  `FoodService.SearchAsync(name)` picks the best Food; convert `quantity`+`unit` to the app's
  grams/servings (prefer the matched food's serving size; fall back to a small density table;
  flag estimates **low-confidence**). The endpoint returns resolved rows + confidence for the
  app's review screen. **Nothing is committed** until the user confirms via the existing
  recipe-ingredient path.

### 7.2 Endpoint
`POST /api/recipes/parse-ingredients` → `{ text }` ⇒ `[{ parsed, matchedFood?, quantity, unit,
confidence }]`. Mobile renders a review list; on confirm it calls the existing recipe save/add.

### 7.3 Why this shape
The LLM does the thing LLMs are good at (messy language → structure) and nothing it's bad at
(authoritative numbers). The DB/providers remain the nutrition source of truth, the user is the
final validator, and the whole feature can be removed by unsetting one config key.

## 8. Infrastructure & delivery
- **IaC:** `infra/main.bicep`, parameterized by `environment` (staging|prod) → isolated stacks
  (Container Apps + Postgres Flexible Server + Key Vault + ACR + Log Analytics), tagged, with
  staging scaled to zero. See `APP_NOTES.md` for the exact deploy commands and the
  new-subscription gotchas (Postgres region restriction; ACR Tasks blocked → local docker build).
- **CI/CD:** `.github/workflows/ci.yml` builds+tests server and app on push; `deploy.yml` is a
  manual, environment-selectable image build + Container App update.
- **Secrets:** Key Vault; locally `dotnet user-secrets`. Never commit secrets; DTOs/params files
  hold placeholders only.

## 9. Working in parallel (read this before starting a task)

Sitos is structured so several agents can build at once with minimal coordination.

### 9.1 The seams that make parallelism safe
1. **Layer dependency rule** (`Core ← Infrastructure ← Api`) — interface changes ripple in one
   direction; an agent editing an `IFoodProvider` impl doesn't touch endpoints.
2. **One file per feature area** — endpoints, DTOs, screens, and providers are each split into
   per-feature files, so two features rarely edit the same file.
3. **Contract-first** — the DTO + endpoint shape is the agreement between backend and mobile
   agents; once it's written, both sides proceed independently against it.
4. **Service interfaces** — `IFoodService`, `IRecipeService`, `IIngredientParser`,
   `ICurrentUser` let an agent build against a stub/contract before the impl exists.

### 9.2 How to decompose a feature into parallel tasks
A typical feature splits into independent tracks that meet at the contract:

```
            ┌─ (A) Contract: add DTO(s) in Contracts/ + mirror in models.dart  ── do first, tiny
            │
  Feature ──┼─ (B) Backend: Core entity/abstraction → migration → Infra service → endpoint
            │
            ├─ (C) Mobile: api_client method → provider → screen(s)            (against the DTO)
            │
            └─ (D) Tests + verify: xUnit for (B) logic; emulator smoke test of (C)
```
- **(A)** is a fast, shared first step — land the contract, then **(B)** and **(C)** run in
  parallel. **(D)** verifies each side.
- Provider/AI integrations (new `IFoodProvider`, the `IIngredientParser` impl) are their own
  isolated track: implement the interface + register in `DependencyInjection.cs`.

### 9.3 Module ownership (who-touches-what — avoid collisions)
| Track | Edits | Rarely needs |
|---|---|---|
| Contract | `Contracts/*Dtos.cs`, `app/lib/models.dart` | everything else |
| Backend feature | `Core/Entities`, `SitosDbContext`, `Infrastructure/Services`, `Api/Endpoints` | app/ |
| Food provider | `Infrastructure/Providers/*`, `DependencyInjection.cs` | Api/, app/ |
| AI parser | `Core/Abstractions/IIngredientParser.cs`, `Infrastructure/.../ClaudeIngredientParser.cs`, DI | app screens |
| Mobile feature | `app/lib/api_client.dart`, `providers.dart`, `screens/*` | server/ |
| Infra/CI | `infra/`, `.github/workflows/` | source |

### 9.4 Conventions (so parallel output stays consistent)
- **Backend:** minimal APIs grouped per feature with `requireAuth`; services own persistence
  and dedup-by-barcode; nutrition normalized per 100g via `NutritionMath`; providers never 500.
- **Migrations:** one per model change, named, committed; never hand-edit a generated migration.
- **Mobile:** all HTTP in `api_client.dart`; one screen per file; mutate then
  `ref.invalidate(provider)`; gate features behind config flags so missing config degrades, not
  crashes.
- **Auth/AI/provider features are config-gated** — absent config ⇒ feature off, app still works.
- **Tests/verify:** backend logic gets xUnit; UI features get an emulator smoke test using the
  `SITOS_TEST_TOKEN` bypass (drive the app against staging without interactive sign-in).
- **Definition of done:** see PRD §7.

### 9.5 The "add a feature" recipe (canonical example: a new logged-quantity field)
1. **Contract:** add field to the relevant `*Dto` and to `models.dart`.
2. **Core:** add the property to the entity (+ enum if needed).
3. **Infrastructure:** `SitosDbContext` config if needed → `dotnet-ef migrations add …`.
4. **Api:** read/write the field in the endpoint; map in the DTO `From(...)`.
5. **Mobile:** send/parse it in `api_client.dart`; surface in the screen + provider.
6. **Verify:** xUnit for any math; emulator smoke test for the UI; deploy to staging.

## 10. Target architecture & evolution (full product)

The current architecture already supports most of the roadmap by extending existing seams.
This section names how each major capability lands without a rewrite.

| Capability | How it extends the current design | New pieces |
|---|---|---|
| **More food providers** (Nutritionix, Edamam, Spoonacular) | Implement `IFoodProvider`, register a typed `HttpClient`; the priority-ordered resolver in `FoodService` picks them up automatically | One provider class + DI line each; API keys in Key Vault |
| **NL ingredient parsing** | `IIngredientParser` (Core) + `ClaudeIngredientParser` (Infra) + a parse endpoint; resolution reuses `FoodService.SearchAsync` | Anthropic SDK; `Ai:*` config; one endpoint + review screen |
| **Community data validation & sharing** | `Food.VerifiedStatus` + `CreatedByUserId` already model it. Add a `FoodContribution` table (raw user submissions) and a **validation worker** that cross-matches submissions and promotes agreed entries to `CommunityValidated`/`OfficialSource` | A background job (hosted service or scheduled Container App job); a contributions table + dedup/merge logic |
| **History & trends** | New read-only endpoints aggregating `DiaryEntry` over date ranges; chart screens in the app | Range-summary endpoints; a charting widget |
| **Microsoft + Apple sign-in** | The OIDC validator is already provider-agnostic — add issuers/audiences via config (or adopt Entra External ID, same `Auth:*` seam) | Config + app sign-in buttons; no API code change |
| **iOS release** | Same Flutter codebase + flavors; add iOS signing, `GIDClientID`/URL schemes, App Store config | iOS build config; CI lane |
| **Offline write queue** | App-side: a local outbox (drift/sqflite) that replays mutations when online; the API stays stateless/idempotent | Local DB + sync logic; idempotency keys on mutating endpoints |
| **Observability & scale** | App Insights is wired via Log Analytics; add dashboards + custom events (AI/provider usage, log latency). Postgres scales vertically first, then read replicas; Container Apps autoscale on concurrency | Dashboards; alerting; idempotency + rate-limit middleware |
| **Search at scale** | Today: cache `ILIKE` + provider top-up. At volume: Postgres full-text (`tsvector`) or a search index; provider calls move behind a short cache/debounce | FTS index migration; optional search service |
| **AI photo recognition** (horizon) | A separate, clearly-bounded vision capability behind its own interface; same "AI proposes, DB + user confirm" rule as the NL parser | Vision model integration; new endpoint + review UI |

**Evolution guardrails (keep these true as it grows):**
- The **layer dependency rule** (`Core ← Infrastructure ← Api`) and **config-gated features**
  never bend — every new external dependency is swappable and degrades gracefully.
- Background/async work (validation, batch imports) runs as a **separate worker**, not inside
  request handlers, so the API stays fast and stateless.
- Mutating endpoints gain **idempotency keys** before offline sync ships.
- The **contract** stays the seam; versioning (e.g. `/api/v2`) is introduced only on a breaking
  change, never casually.

## 11. Glossary
**Backing food** — the per-serving `Food` a recipe maintains so a serving logs like any food.
**Cache-first** — read local DB before calling a provider; persist provider hits.
**Config-gated** — a feature that is inert unless its config (auth issuer, AI key, provider key)
is present, so the app degrades gracefully.
**Source of truth** — the database for all nutrition; providers and the LLM are inputs to it.
