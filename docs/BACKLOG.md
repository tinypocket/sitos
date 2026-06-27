# Sitos — Backlog

**Last updated:** 2026-06-27 · **Companion:** [ROADMAP.md](ROADMAP.md) · [PRD.md](PRD.md) · [ARCHITECTURE.md](ARCHITECTURE.md)

Epics → stories. Each story has **Priority** (P0–P3, see [ROADMAP.md](ROADMAP.md)), **Effort**
(S/M/L), **Status** (✅ done · 🚧 in flight · ⬜ todo), and **Track** — the parallel-work lane from
[ARCHITECTURE.md §9.3](ARCHITECTURE.md): `Contract` · `Backend` · `Provider` · `AI` · `Mobile` · `Infra`.

> How to use: pick a `⬜ todo` story; if it spans tracks, land the **Contract** sub-task first,
> then run **Backend** and **Mobile** in parallel, then **verify**. Mark status here as you go.

---

## EPIC A — Core logging loop
| ID | Story | Pri | Eff | Status | Track |
|----|-------|-----|-----|--------|-------|
| A1 | Barcode scan → cache-first lookup → log to diary | P0 | L | ✅ | Backend+Mobile |
| A2 | Daily diary: calorie ring, macros, entries | P0 | M | ✅ | Mobile |
| A3 | Meal grouping (B/L/D/Snacks) + subtotals | P1 | M | ✅ | Backend+Mobile |
| A4 | Edit / delete / tap-to-edit entry (qty, meal) | P1 | S | ✅ | Mobile |
| A5 | Recent-foods quick-add strip | P1 | S | ✅ | Backend+Mobile |
| A6 | Manual barcode entry (camera fallback) | P2 | S | ✅ | Mobile |
| A7 | Quick-add calories (number, no food) | P2 | S | ⬜ | Backend+Mobile |
| A8 | Daily/water reminder notifications | P3 | M | ⬜ | Mobile |

## EPIC B — Food data & providers
| ID | Story | Pri | Eff | Status | Track |
|----|-------|-----|-----|--------|-------|
| B1 | Open Food Facts provider (barcode + fast search) | P0 | M | ✅ | Provider |
| B2 | USDA fallback provider | P1 | S | ✅ | Provider |
| B3 | Persist provider results (stable ids for logging) | P0 | S | ✅ | Backend |
| B4 | Custom user foods (incl. scan-miss prefill) | P1 | M | ✅ | Backend+Mobile |
| B5 | Nutritionix provider | P1 | M | ⬜ | Provider |
| B6 | Edamam provider | P1 | M | ⬜ | Provider |
| B7 | Serving-size / density table for unit conversion | P2 | M | ⬜ | Backend |
| B8 | Postgres full-text search index (scale) | P2 | M | ⬜ | Backend+Infra |
| B9 | Open Beauty Facts / supplements (opportunistic) | P3 | M | ⬜ | Provider |

## EPIC C — Recipes & natural-language entry
| ID | Story | Pri | Eff | Status | Track |
|----|-------|-----|-----|--------|-------|
| C1 | Recipe model + per-serving backing food | P0 | L | ✅ | Backend |
| C2 | Recipe CRUD + log N servings to a meal | P0 | M | ✅ | Backend+Mobile |
| C3 | Recipe editor + ingredient picker (search) | P1 | M | ✅ | Mobile |
| C4 | **NL parse contract** (`parse-ingredients` DTO) | P0 | S | ⬜ | Contract |
| C5 | **`IIngredientParser` + ClaudeIngredientParser** (Haiku 4.5, structured output, config-gated) | P0 | M | 🚧 | AI |
| C6 | Parse endpoint: parse → resolve foods → confidence | P0 | M | ⬜ | Backend |
| C7 | "Smart add" review screen (confirm/fix rows) | P0 | M | ⬜ | Mobile |
| C8 | NL entry usage logging + cost guard / feature flag | P1 | S | ⬜ | AI+Infra |
| C9 | Recipe scaling / photos / share recipes | P2 | L | ⬜ | Backend+Mobile |

## EPIC D — Goals & insights
| ID | Story | Pri | Eff | Status | Track |
|----|-------|-----|-----|--------|-------|
| D1 | Calorie goal + progress ring | P0 | S | ✅ | Backend+Mobile |
| D2 | Macro targets + progress bars | P1 | M | ✅ | Backend+Mobile |
| D3 | History & trends (7/30-day charts) — range-summary endpoint + chart screen | P1 | L | ⬜ | Backend+Mobile |
| D4 | Weekly summary | P2 | M | ⬜ | Backend+Mobile |
| D5 | Streaks / adherence nudges | P2 | M | ⬜ | Mobile |
| D6 | Adaptive goals | P3 | L | ⬜ | Backend |

## EPIC E — Identity, auth & privacy
| ID | Story | Pri | Eff | Status | Track |
|----|-------|-----|-----|--------|-------|
| E1 | Provider-agnostic OIDC validation + per-user isolation | P0 | M | ✅ | Backend |
| E2 | Google Sign-In (app) | P0 | M | ✅ | Mobile |
| E3 | Dev/staging test-auth bypass (for automated tests) | P1 | S | ✅ | Backend+Mobile |
| E4 | **Auth decision**: confirm direct-Google vs Entra before launch | P0 | S | ⬜ | — (decision) |
| E5 | Microsoft sign-in (config-only) | P1 | S | ⬜ | Mobile+Infra |
| E6 | Apple sign-in (required if iOS offers social login) | P1 | M | ⬜ | Mobile+Infra |
| E7 | **Disable test-auth flag before public exposure** | P0 | S | ⬜ | Infra |
| E8 | Account data **export** | P1 | M | ⬜ | Backend+Mobile |
| E9 | Account **delete** (cascade user data) | P1 | M | ⬜ | Backend+Mobile |

## EPIC F — Platform, deploy & observability
| ID | Story | Pri | Eff | Status | Track |
|----|-------|-----|-----|--------|-------|
| F1 | Bicep IaC (Container Apps + Postgres + KV + ACR) | P0 | L | ✅ | Infra |
| F2 | Staging environment deploy + verified | P0 | M | ✅ | Infra |
| F3 | Staging/prod flavors + env-aware deploy workflow | P1 | M | ✅ | Infra+Mobile |
| F4 | **Production deploy** (`sitos-prod`) | P0 | M | ⬜ | Infra |
| F5 | Cold-start mitigation (warm prod / raise client timeout) | P1 | S | ⬜ | Infra+Mobile |
| F6 | Fix CI deploy lane for ACR-Tasks restriction (local build/push) | P1 | S | ⬜ | Infra |
| F7 | App Insights dashboards (log latency, AI/provider usage) + alerts | P2 | M | ⬜ | Infra |
| F8 | Store rollout (Play internal → prod; App Store later) | P1 | M | ⬜ | Infra |

## EPIC G — Community data validation & sharing
| ID | Story | Pri | Eff | Status | Track |
|----|-------|-----|-----|--------|-------|
| G1 | `FoodContribution` table (raw user submissions) | P1 | S | ⬜ | Backend |
| G2 | Validation worker: cross-match + promote to verified | P1 | L | ⬜ | Backend+Infra |
| G3 | Verified badges in search/detail UI | P2 | S | ⬜ | Mobile |
| G4 | Trust model (concurring-submissions threshold) | P2 | M | ⬜ | Backend (+decision) |

## EPIC H — Monetization (proposed, TBD)
| ID | Story | Pri | Eff | Status | Track |
|----|-------|-----|-----|--------|-------|
| H1 | Decide model (free core + premium tier) | P2 | S | ⬜ | — (decision) |
| H2 | Entitlements + paywall surfaces | P2 | L | ⬜ | Backend+Mobile |
| H3 | Store billing integration | P2 | L | ⬜ | Mobile+Infra |

## EPIC I — Horizon (💤 not committed)
| ID | Story | Pri | Eff | Status | Track |
|----|-------|-----|-----|--------|-------|
| I1 | AI photo recognition (propose → DB + user confirm) | P3 | L | ⬜ | AI+Backend+Mobile |
| I2 | Social: share recipes | P3 | L | ⬜ | Backend+Mobile |
| I3 | Coach/clinician shared views | P3 | L | ⬜ | Backend+Mobile |
| I4 | Offline write queue + idempotent mutations | P1 | L | ⬜ | Mobile+Backend |
| I5 | Water & weight tracking | P2 | M | ⬜ | Backend+Mobile |

---

### Snapshot
- **Shipped:** Phase 0 + most of the core loop, recipes, meals, macros, Google auth, staging.
- **In flight:** C5 (NL parser implementation).
- **Next P0s:** C4/C6/C7 (NL feature), F4 (prod), E4/E7 (auth decision + disable test flag).
- Keep this file honest — flip status as work lands; add stories as they're discovered.
