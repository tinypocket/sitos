# Sitos — Product Requirements Document (full product)

**Status:** Living document · **Owner:** Product/Eng · **Last updated:** 2026-06-27
**Companion docs:** [ARCHITECTURE.md](ARCHITECTURE.md) · [ROADMAP.md](ROADMAP.md) · [BACKLOG.md](BACKLOG.md)

---

## 1. Vision & north star

**Vision.** Make calorie and macro tracking *effortless enough to become a daily habit*, on
the back of the most trustworthy, community-built food database.

**North-star metric.** **Weekly logging retention** — the % of activated users who log food on
≥4 of 7 days. Everything in the product is judged by whether it moves this. Tracking dies from
friction and from distrust of the numbers; Sitos attacks both.

**Strategic bets**
1. **Speed wins habits.** The scan→log loop must be faster than any competitor (target < 5s
   from app open). Natural-language entry and one-tap re-log compound this.
2. **Trust compounds.** A cache-first, multi-source, community-validated food database gets
   more correct and more complete with every scan — a durable moat that improves with usage.
3. **Families and real cooking.** Recipes + meal-splitting serve the home cook other trackers
   treat as an afterthought, and seed high-value user-contributed data.
4. **One codebase, two platforms.** Flutter ships Android now and iOS later from the same code;
   a secure cloud backend keeps data portable and analyzable.

## 2. Strategy & positioning

| | Sitos | Typical competitor |
|---|---|---|
| Logging speed | Scan / NL / quick-add, < 5s | Search-heavy, slow |
| Data trust | Cache + multi-source + community validation, user-editable | Single DB, stale, locked |
| Recipes / families | First-class meal-splitting | Afterthought or premium-walled |
| Data ownership | User's data in your own Postgres; analyzable | Locked in vendor |
| AI | Narrow, deterministic-nutrition parsing | Opaque AI guesses |

**Wedge → expansion.** Win the barcode-scanning + family-cooking user with raw speed and
trustworthy data; expand into insights, breadth of food sources, and platforms.

## 3. Users & jobs-to-be-done

| Persona | Context | Job-to-be-done | What they need from Sitos |
|---|---|---|---|
| **Habitual tracker** | Logs daily, goal-driven | "Log what I eat in seconds and know if I'm under my goal." | Instant scan, quick re-log, clear daily ring + macros |
| **Home cook / family** | Cooks for several people | "Build a meal from ingredients, split by portions, log my share." | Recipes, meal-splitting, NL ingredient entry |
| **Data-conscious user** | Distrusts food DBs | "Trust the numbers; fix them when wrong." | Multi-source data, edit/contribute, verified badges |
| *(future)* **Coach / clinician** | Guides others | "See a client's adherence." | Shared/exported views (post-MVP) |

## 4. Product principles
1. **Logging speed beats feature breadth.** Every feature is judged against the scan→log loop.
2. **Deterministic nutrition.** The database is the source of truth for calories/macros. AI and
   providers *propose*; the database and the user *confirm*.
3. **Cache everything we fetch.** Every external lookup is persisted, growing a shared asset.
4. **The user is the final validator.** Anything ambiguous is surfaced, never silently committed.
5. **Provider-agnostic seams.** Food sources and the identity provider are swappable behind interfaces.
6. **Degrade, don't crash.** A missing provider/AI/auth config disables a feature; the app keeps working.
7. **Own the data.** All product data lives in our Postgres so analytics never depend on a vendor.

## 5. Capability catalog (full product)

Status: ✅ shipped · 🚧 in flight · ⬜ planned · 💤 horizon. Sequencing in [ROADMAP.md](ROADMAP.md);
work items in [BACKLOG.md](BACKLOG.md).

### 5.1 Logging
- ✅ Barcode scan → instant nutrition → log to a daily diary (quantity in servings/grams)
- ✅ Daily diary: calorie ring vs goal, macro progress bars, **meal grouping** + per-meal subtotals
- ✅ Edit / delete entries; tap-to-edit quantity/meal
- ✅ Food search (cache + Open Food Facts), persisted results
- ✅ Recent-foods quick-add strip
- ✅ Manual barcode entry (camera fallback)
- ⬜ Quick-add calories (log a number without a food)
- 💤 Voice logging end-to-end; AI photo recognition

### 5.2 Food data
- ✅ Cache-first resolution; Open Food Facts (primary) → USDA (fallback); persist every hit
- ✅ Custom user foods (incl. from a failed scan, barcode prefilled)
- ⬜ More providers: Nutritionix, Edamam, Spoonacular (pluggable `IFoodProvider`)
- ⬜ **Community data validation & sharing**: cross-match user submissions, promote agreed
  entries to a verified shared dataset (`VerifiedStatus` already modeled)
- ⬜ Better serving-size + density data for unit conversion

### 5.3 Recipes & meal splitting
- ✅ Define a recipe (ingredients + servings); server computes per-serving nutrition (backing food)
- ✅ Log N servings to a meal; edit/delete recipes; ingredient picker
- 🚧 **Natural-language ingredient entry** (LLM parses + normalizes; user confirms) — see §7
- ⬜ Recipe scaling, photos, sharing recipes between users

### 5.4 Goals & insights
- ✅ Daily calorie target + optional protein/carb/fat targets, with progress bars
- ⬜ History & trends (7/30-day charts; weekly summaries)
- ⬜ Streaks / adherence nudges
- 💤 Adaptive goals; coach view

### 5.5 Identity, sync & platform
- ✅ Google Sign-In (direct OIDC, provider-agnostic validation), per-user data isolation
- ✅ Dev/staging test-auth bypass for automated testing
- ⬜ Microsoft + Apple sign-in (config-only on existing OIDC validation)
- ⬜ iOS release; offline write queue + sync
- ✅ Azure deploy (Container Apps + Postgres + Key Vault), staging; ⬜ prod
- ⬜ Observability (App Insights dashboards, AI/provider usage), CI deploy hardening

### 5.6 Trust, privacy, monetization
- ✅ Per-user isolation, OIDC validation, secrets in Key Vault, providers never 500
- ⬜ Account/data export & delete (privacy)
- ⬜ **Monetization (proposed, TBD):** free core; premium tier (history depth, advanced
  insights, unlimited recipes, integrations). Decide before launch.

## 6. Non-goals (for now)
AI photo recognition · social feed/friends UI (validation *backend* is in scope) · workout/
burn tracking · medical/clinical claims.

## 7. Spotlight feature: natural-language ingredient entry  ⭐

**User story.** *"While cooking for my family I type or dictate ‘5 eggs, 2 tablespoons of oil,
some salt, half a cup of cottage cheese' and Sitos figures out the ingredients, quantities, and
units, finds each food, and adds them to my recipe — I just confirm."*

**Behavior:** free-form text → **LLM (Claude Haiku 4.5) parses + normalizes** into structured
`{name, quantity, unit, note}` → backend **resolves each to a Food** (cache → Open Food Facts)
and converts to grams/servings with a confidence → app shows a **review screen** → user fixes
low-confidence rows → confirm adds them via the existing recipe path.

**Guardrails:** the LLM never produces nutrition numbers; nothing auto-commits; feature is
config-gated (no key ⇒ hidden, manual add still works); only ingredient text is sent (no PII);
cost target ≪ \$0.01/parse; latency < ~3s. Design detail in [ARCHITECTURE.md §7](ARCHITECTURE.md).

**Success:** ≥ 60% of parsed rows accepted without edit; recipe-creation time materially down.

## 8. Success metrics (KPI framework)

| Stage | Metric | Why |
|---|---|---|
| **Activation** | % of new users who log ≥1 food in first session | First value delivered |
| **Engagement** | Logs per active day; DAU/WAU | Habit strength |
| **Retention (north star)** | % logging ≥4/7 days (W1, W4) | The thing that matters |
| **Speed** | Median app-open → first log time | Core promise |
| **Data quality** | % barcode lookups with complete macros; % NL rows accepted unedited | Trust |
| **Cost** | Infra + AI \$ per monthly active user | Sustainability |

## 9. Risks & mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Food-data quality/coverage gaps | Users distrust numbers | Multi-source + cache + community validation + user edit |
| Provider rate limits / downtime | Lookups fail | Cache-first; fallback chain; timeouts never 500 |
| LLM cost / latency / wrong parse | Cost blowout, bad UX | Cheapest model + structured output + user-confirm + feature flag + usage logging |
| Auth/privacy/security | Breach, churn | OIDC validation, per-user isolation, Key Vault, export/delete |
| iOS/cross-platform parity | Half the market | Flutter single codebase; iOS is a release task, not a rewrite |
| New-subscription Azure limits | Deploy friction | Documented workarounds in APP_NOTES.md |
| Single-maintainer bus factor | Velocity/continuity | Docs + contract-first + multi-agent architecture |

## 10. Dependencies & assumptions
- External: Open Food Facts, USDA FoodData Central, Google/Entra OIDC, Anthropic API, Azure.
- Assumes a single developer + AI agents; the architecture is structured for parallel agent work
  (see [ARCHITECTURE.md §9](ARCHITECTURE.md)).

## 11. Release gating (definition of done)
Backend builds + unit tests pass; `flutter analyze` clean + app builds; happy path verified
end-to-end against staging; feature degrades gracefully when its dependency is absent.

## 12. Open questions
- NL volume→grams: matched-food serving vs density table vs LLM-suggested grams (flagged)?
  **Leaning:** matched-food serving → density fallback → low-confidence flag.
- Monetization model & timing.
- Identity: stay on direct-Google or adopt Entra External ID before launch (multi-provider)?
- Community-validation trust model: how many concurring submissions promote a food to "verified"?
