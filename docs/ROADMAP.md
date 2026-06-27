# Sitos — Roadmap & Priorities

**Last updated:** 2026-06-27 · **Companion:** [PRD.md](PRD.md) · [BACKLOG.md](BACKLOG.md) · [ARCHITECTURE.md](ARCHITECTURE.md)

How we sequence work and why. Phases are themes, not hard dates. Each phase has an **objective**,
the **priority items**, and an **exit criterion** that gates the next phase. Story-level detail
(with priority/effort/status and the parallel-work track) is in [BACKLOG.md](BACKLOG.md).

## Prioritization model
Each backlog item carries a **priority** and a rough **effort**:

- **P0** — must-have for the current phase / blocks others.
- **P1** — high value, scheduled this/next phase.
- **P2** — valuable, not urgent.
- **P3** — nice-to-have / opportunistic.
- Effort: **S** (≲½ day) · **M** (~1–2 days) · **L** (multi-day).

We sequence by: *(1)* protect the core loop, *(2)* unblock launch, *(3)* deepen trust & breadth,
*(4)* expand platforms & reach. Within a phase, do P0s before P1s; pull P2/P3 when cheap or
adjacent.

---

## Phase 0 — Foundations ✅ (done)
**Objective:** prove the end-to-end loop and stand up the platform.
- Scan → nutrition → diary; meals; macros & goals; recipes/meal-splitting; search; custom foods;
  recent quick-add. Google auth. Azure **staging** deploy. Test-auth bypass for automated testing.
- **Exit (met):** the full loop works live on a device against Azure; CI green.

## Phase 1 — Launch-ready 🚧 (now)
**Objective:** make Sitos shippable to first real users.
- **P0** Natural-language ingredient entry (spotlight feature).
- **P0** Production environment deploy (`sitos-prod`) + cold-start mitigation (keep staging→prod
  parity; warm prod / raise client timeout).
- **P0** Auth decision + hardening: confirm direct-Google vs Entra; add **Microsoft + Apple**
  (config-only); turn **off** the staging test-auth flag before any public exposure.
- **P1** Account data **export & delete** (privacy/store requirement).
- **P1** **Caloric-needs guide** — onboarding calculator so a new user gets a sensible target.
- **P1** First **design pass** (visual/UX polish) and error/empty-state polish; CI **deploy**
  lane fixed for the ACR-Tasks restriction.
- **P2** Quick-add calories (number without a food).
- **Exit:** a new user can sign in, get a target, scan/log, build a recipe (incl. NL), and hit a
  goal — on prod — with graceful failure modes; privacy controls exist.

## Phase 2 — Trust & breadth (next)
**Objective:** make the data the moat and surface insight.
- **P1** More providers: **Nutritionix**, **Edamam** (and barcode/UPC coverage), via `IFoodProvider`.
- **P1** **Community data validation v1**: contributions table + worker that cross-matches and
  promotes agreed foods to verified; show verified badges.
- **P1** **History & trends**: 7/30-day calorie/macro charts + weekly summary.
- **P2** **Faster meal logging**: multi-ingredient entry, **repeatable meal templates**,
  customizable meals/snacks, multi-barcode scan, recipe import from URL.
- **P2** **Full nutrient tracking** (sodium, cholesterol, fiber, sugar, …).
- **P2** **Smarts**: suggested/repeat meals + favorite-food detection.
- **P2** **Weight & water tracking** (manual).
- **P2** Search quality (Postgres full-text; better serving/density data for unit conversion);
  streaks / adherence nudges.
- **Exit:** food coverage + correctness measurably up; users can see trends; logging is faster;
  verified data exists.

## Phase 3 — Reach & durability (later)
**Objective:** more platforms, more resilience, a business model.
- **P1** **iOS release** (same Flutter codebase + flavors; signing, Apple sign-in already in P1).
- **P1** **Offline write queue** + idempotent mutations.
- **P2** **Fitness & health**: activity/burn offset + **health-app integrations** (Health Connect /
  Apple Health / Google Fit / Fitbit auto-import of activity + weight).
- **P2** **Weekly meal planning**; **kids mode**.
- **P2** **Observability**: App Insights dashboards (log latency, AI/provider usage), alerting.
- **P2** **Monetization**: free core + premium tier (history depth, advanced insights, unlimited
  recipes/integrations) — decide and implement.
- **Exit:** Sitos runs on iOS + Android, tolerates offline use, imports activity/weight, and has a
  path to revenue.

## Phase 4 — Horizon (💤 explore, not committed)
- **AI vision capture** (same "AI proposes, DB + user confirm" rule): photograph a dish for an
  ingredient breakdown or a quick "simple-mode" estimate; photo of loose ingredients → list +
  portions; recipe-from-image (screenshot / cookbook page).
- **Circles & sharing**: link family/friends, portion a meal out to circle members, share intake
  & stats, share recipes, coach/clinician views.
- Adaptive goals; deeper insights.

---

## Theme cross-cuts (apply every phase)
- **Security & privacy:** per-user isolation, secrets in Key Vault, export/delete, least-privilege.
- **Cost:** cheapest-capable AI + prompt caching; scale-to-zero staging; watch \$/MAU.
- **Quality bar:** PRD §11 definition of done on every item.
- **Parallelism:** decompose each item into the tracks in [ARCHITECTURE.md §9](ARCHITECTURE.md).

## Sequencing rationale (why this order)
1. **Phase 1 protects launch**: the NL feature is the biggest remaining friction win, and prod +
   auth + privacy are table-stakes to expose the app to anyone.
2. **Phase 2 builds the moat**: once people are logging, data breadth/trust and insight drive
   the north-star metric (weekly logging retention) more than new logging surfaces.
3. **Phase 3 expands reach** only after the core is sticky — iOS and offline multiply an already
   good loop; monetization follows retention.
4. **Phase 4** is deliberately uncommitted — high-cost bets (vision AI, social) wait for signal.
