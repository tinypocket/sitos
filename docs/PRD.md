# Sitos — Product Requirements Document

**Status:** Living document · **Owner:** Product/Eng · **Last updated:** 2026-06-27

---

## 1. Context & problem

People who want to track calories abandon most apps because logging is *work*: searching
for foods, guessing serving sizes, and re-entering the same meals. Sitos's bet is that the
fastest possible logging loop — **scan a barcode → instant nutrition → one tap to log** —
plus a server that quietly builds a shared, trustworthy food database, produces a tracker
people actually keep using.

Sitos exists to make daily calorie + macro tracking *low-friction enough to become a habit*,
while accumulating a high-quality, community-validated food dataset as a durable asset.

## 2. Goals & non-goals

**Goals (what success looks like)**
- A user can log a scanned food in **under 5 seconds** from app open.
- Nutrition data is correct and **cached server-side** so repeat lookups are instant and the
  dataset grows with use.
- Users can define their own foods and **multi-ingredient recipes**, then log a portion.
- The product works **offline-tolerant** for recent foods and degrades gracefully when a
  provider is slow or down.
- The backend is **secure** (per-user data isolation, validated identity) and **cheap to run**.

**Non-goals (explicitly out of scope for now)**
- AI photo recognition of meals.
- Social feed / friends / sharing UI (data-validation backend is in scope; social UI is not).
- Workout/exercise tracking and calorie *burn*.
- Medical/clinical claims.

## 3. Users & primary jobs-to-be-done

| Persona | JTBD |
|---|---|
| **Habitual tracker** | "Log what I eat in seconds and see if I'm under my goal today." |
| **Home cook / family** | "Build a meal from ingredients, split it across portions, log my share." |
| **Data-conscious user** | "Trust the numbers, and add my own foods when the DB is wrong/missing." |

## 4. Product principles
1. **Logging speed beats feature breadth.** Every feature is judged by whether it keeps the
   scan→log loop fast.
2. **Deterministic nutrition.** The calorie/macro source of truth is the database, never an
   LLM guess. AI may *propose*; the database (and the user) *confirm*.
3. **Cache everything we fetch.** Any external lookup is persisted, growing a shared asset.
4. **The user is the final validator.** Anything ambiguous is surfaced for confirmation, not
   silently committed.
5. **Provider-agnostic at the seams.** Food sources and the identity provider are swappable
   behind interfaces.

## 5. Feature set

### 5.1 Shipped (v0 → staging)
- **Barcode scan → nutrition → log.** Camera scanner; cache-first lookup (Open Food Facts →
  USDA fallback); add to a daily diary with quantity (servings/grams).
- **Daily diary.** Calorie ring vs goal, macro progress bars, **meal grouping** (Breakfast/
  Lunch/Dinner/Snacks) with per-meal subtotals; edit/delete entries.
- **Food search.** Fast full-text search (cache + Open Food Facts), persisted results.
- **Custom foods.** User-entered foods (incl. from a failed scan, barcode prefilled).
- **Recipes / meal splitting.** Define a dish from ingredients + number of servings; the
  server computes per-serving nutrition and lets the user log N portions to a meal.
- **Goals.** Daily calorie target + optional protein/carb/fat targets.
- **Auth.** Google Sign-In (direct OIDC; provider-agnostic validation). Microsoft + Apple
  are planned config-only additions.
- **Deployment.** Azure (Container Apps + PostgreSQL + Key Vault), staging environment live.

### 5.2 Next: Natural-language ingredient entry  ⭐ (this cycle)

**User story.** *"While making a meal for my family, I type or dictate ‘5 eggs, 2 tablespoons
of oil, some salt, half a cup of cottage cheese' and Sitos figures out the ingredients,
quantities, and units, finds each food, and adds them to my recipe — I just confirm."*

**Why now.** Adding ingredients one-by-one (search → pick → quantity, repeated) is the
slowest path in the app. Natural-language entry collapses a whole recipe into one sentence.

**Behavior**
1. User enters free-form text in the recipe editor ("smart add" field) — typed or via the
   device's voice-to-text.
2. The backend uses an **LLM (Claude Haiku 4.5) for parsing + normalization only**: it turns
   the text into a structured list of `{ name, quantity, unit, rawText, note }` items —
   normalizing "half a cup" → `0.5 cup`, "5 eggs" → `5 each`, "some salt" → quantity unknown
   with a note.
3. For each parsed item the backend **resolves a Food** via the existing food search
   (cache → Open Food Facts), converts the parsed quantity/unit into the app's grams/servings
   model, and attaches a **confidence**.
4. The app shows a **review screen**: matched food, quantity, and a confidence chip per row.
   The user fixes any low-confidence rows (wrong match, ambiguous "some"), then confirms.
5. On confirm, the items are added to the recipe through the existing recipe-ingredient path.

**Requirements & guardrails**
- The LLM **never** produces calorie/macro numbers — only structure. Nutrition comes from the
  resolved Food.
- **Nothing is auto-committed.** Parsed ingredients are a proposal; the user confirms.
- **Graceful degradation:** if the LLM is unconfigured/unavailable/over budget, the smart-add
  field is hidden and manual add still works. A parse failure returns a clear, retryable error.
- **Cost control:** parsing is a small, cached-prompt call (see Architecture §"AI"); target
  well under \$0.01 per parse. The feature is feature-flagged and usage is logged.
- **Privacy:** only the ingredient text is sent to the model; no PII, no diary history.
- **Latency target:** parse + resolve round-trip under ~3s for a typical 3–6 ingredient list.

**Success metric:** ≥ 60% of parsed rows accepted without edit; recipe-creation time down
materially vs manual add.

### 5.3 Later (roadmap)
- Microsoft + Apple sign-in (config-only on the existing OIDC validation).
- More food providers: Nutritionix, Edamam, Spoonacular.
- **Community data validation & sharing** — cross-match user-submitted foods, promote
  agreed-upon entries to a verified shared dataset (the `VerifiedStatus` field already exists).
- Recent-meal quick re-log; water & weight tracking; history/trends charts.
- iOS release; offline write queue.
- AI photo recognition (explicitly post-MVP).

## 6. Cross-cutting requirements
- **Security:** HTTPS only; JWT bearer validated against the configured OIDC issuer; every
  query scoped to the caller's user id; secrets in Key Vault; least-privilege DB access.
- **Reliability:** provider timeouts never 500 the request — fall back to cache/empty and log.
- **Cost:** staging scales to zero; Burstable Postgres; AI calls use the cheapest capable
  model with prompt caching.
- **Privacy:** the user's food/diary data is the user's; identity data is mirrored locally so
  analytics never depend on the identity provider.
- **Observability:** structured logs + Azure App Insights; provider failures and AI usage are
  visible.

## 7. Release gating
A feature is "done" when: backend builds + unit tests pass; `flutter analyze` clean + app
builds; the happy path is verified end-to-end against staging; and it degrades gracefully when
its dependency (provider, AI, auth) is absent.

## 8. Open questions
- Volume→grams conversion for the NL parser: static density table vs per-food serving vs
  asking the LLM for grams directly (with user confirmation)? **Leaning:** prefer the matched
  food's serving size; fall back to a small density table; mark anything estimated low-confidence.
- Should NL parsing also power **diary** quick-add (not just recipes)? Likely yes in a later
  pass; recipes first.
