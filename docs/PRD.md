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

### 5.1 Logging & capture
- ✅ Barcode scan → instant nutrition → log to a daily diary (quantity in servings/grams)
- ✅ Daily diary: calorie ring vs goal, macro progress bars, **meal grouping** + per-meal subtotals
- ✅ Edit / delete entries; tap-to-edit quantity/meal
- ✅ Food search (cache + Open Food Facts), persisted results
- ✅ Recent-foods quick-add strip
- ✅ Manual barcode entry (camera fallback)
- ⬜ Quick-add calories (log a number without a food)
- ⬜ **Multi-barcode scan** — scan several packaged items in one session, then review/log together
- ⬜ **Customizable meals & snacks** — rename/add/remove meal slots and set how many per day
- 💤 Voice logging end-to-end

### 5.2 AI capture (vision & language)
- 🚧 **Natural-language ingredient entry** (LLM parses + normalizes; user confirms) — see §7
- 💤 **Scan a dish → ingredient breakdown** — photo a plated meal, get its likely ingredients + portions
- 💤 **Scan a dish → quick estimate ("simple mode")** — one calorie/macro estimate, no breakdown
- 💤 **Photo of multiple ingredients → list + portions** — e.g. "3 medium cucumbers" (count + size estimate)
- 💤 **Recipe from image** — screenshot or photo of a cookbook page → a structured meal (incl. dish photo)

> All AI capture follows the same rule as §7: AI **proposes** structure/estimates; the food DB
> and the **user confirm** before anything is logged. Each is config-gated and removable.

### 5.3 Recipes & meals
- ✅ Define a recipe (ingredients + servings); server computes per-serving nutrition (backing food)
- ✅ Log N servings to a meal; edit/delete recipes; ingredient picker
- ⬜ **Multi-ingredient meal entry** — add several ingredients at once when logging a meal
- ⬜ **Repeatable meal templates** — group foods you eat together and re-log the set in one tap
- ⬜ **Recipe import from URL**
- 💤 **Recipe import from screenshot / cookbook photo** (vision; see §5.2)
- ⬜ Recipe scaling, photos, sharing recipes between users

### 5.4 Food data & nutrition
- ✅ Cache-first resolution; Open Food Facts (primary) → USDA (fallback); persist every hit
- ✅ Custom user foods (incl. from a failed scan, barcode prefilled)
- ⬜ More providers: Nutritionix, Edamam, Spoonacular (pluggable `IFoodProvider`)
- ⬜ **Community data validation & sharing**: cross-match user submissions, promote agreed
  entries to a verified shared dataset (`VerifiedStatus` already modeled)
- ⬜ Better serving-size + density data for unit conversion
- ⬜ **Full nutrient tracking** beyond core macros — sodium, cholesterol, fiber, sugar, etc.

### 5.5 Goals, insights & planning
- ✅ Daily calorie target + optional protein/carb/fat targets, with progress bars
- ⬜ **Caloric-needs guide** — onboarding calculator (age/sex/height/weight/activity → suggested target)
- ⬜ History & trends (7/30-day charts; weekly summaries)
- ⬜ Streaks / adherence nudges
- ⬜ **Suggested meals** — re-surface your repeat meals; new recipes from ingredients you've used
- ⬜ **Favorite foods/ingredients detection** — learn your staples to power suggestions
- 💤 **Weekly meal planning**
- 💤 Adaptive goals; coach view

### 5.6 Circles (family & friends)
- 💤 **Link a circle** of family/friends
- 💤 **Portion a meal to the circle** — one person builds a meal, splits servings, and assigns
  portions to chosen circle members (auto-logs to their diaries on accept)
- 💤 **Share calorie intake & stats** with your circle

### 5.7 Fitness & health
- ⬜ **Weight tracker** (manual entry now; automated via integrations)
- 💤 **Activity/fitness tracking that offsets calories** (burn)
- 💤 **Health-app integrations** — auto-import activity + weight from Health Connect / Apple
  Health / Google Fit / Fitbit

### 5.8 Modes & experience
- ⬜ **Design pass** — visual + UX polish across the app
- 💤 **Kids mode** — simplified UI and fast/easy meal adjustments for children

### 5.9 Identity, sync & platform
- ✅ Google Sign-In (direct OIDC, provider-agnostic validation), per-user data isolation
- ✅ Dev/staging test-auth bypass for automated testing
- ⬜ Microsoft + Apple sign-in (config-only on existing OIDC validation)
- ⬜ iOS release; offline write queue + sync
- ✅ Azure deploy (Container Apps + Postgres + Key Vault), staging; ⬜ prod
- ⬜ Observability (App Insights dashboards, AI/provider usage), CI deploy hardening

### 5.10 Trust, privacy, monetization
- ✅ Per-user isolation, OIDC validation, secrets in Key Vault, providers never 500
- ⬜ Account/data export & delete (privacy)
- ⬜ **Monetization (proposed, TBD):** free core; premium tier (history depth, advanced
  insights, unlimited recipes, integrations). Decide before launch.

## 6. Near-term exclusions (planned later, not rejected)
The catalog above is the long-term product. To launch fast and protect the core loop, these
are **out of the near-term (Phase 1–2) scope** even though they're on the roadmap: AI vision
capture (dish & ingredient photos, recipe-from-image), circles/social sharing, fitness/burn
tracking + health-app integrations, weekly meal planning, and kids mode. **Hard non-goal:**
medical/clinical claims or advice.

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

## 12. Open questions / decisions needed from you

These are product decisions only you can make; each is tracked in [BACKLOG.md](BACKLOG.md) so
work doesn't stall waiting on it. Recommendations are mine, not commitments.

1. **Identity before launch** *(BACKLOG E4)* — stay on **direct Google Sign-In** for now and add
   Microsoft/Apple via config, or adopt **Entra External ID** (one tenant federates all three)?
   *Recommendation:* ship on direct-Google to launch faster; revisit Entra only if multi-IdP
   management becomes painful. Either way the OIDC validation seam doesn't change.
2. **Monetization model & timing** *(BACKLOG H1)* — free-only for now, or **free core + premium**
   (history depth, advanced insights, unlimited recipes, integrations)? When do we introduce it?
   *Recommendation:* free through Phase 2; design the premium line then, gate on retention.
3. **Community-validation trust model** *(BACKLOG G4)* — how many independent, concurring user
   submissions promote a food to **verified**? What about conflicting values?
   *Recommendation:* start at **≥3 concurring within tolerance** → `CommunityValidated`; surface
   conflicts for review rather than auto-merging.
4. **NL volume→grams conversion** *(BACKLOG B7/C6)* — for "2 tablespoons" / "half a cup", prefer
   the **matched food's serving size**, a **static density table**, or **LLM-suggested grams**?
   *Recommendation:* matched-food serving → density-table fallback → flag anything estimated as
   **low-confidence** for user review.
5. **NL entry scope** — does natural-language entry also power **diary** quick-add, or recipes
   only for the first release? *Recommendation:* recipes first; extend to diary in a later pass.
