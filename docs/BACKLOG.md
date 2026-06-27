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
| A9 | Multi-barcode scan (scan several items, review, log together) | P2 | M | ⬜ | Mobile |
| A10 | Customizable meals & snacks (rename/add/remove slots, count per day) | P2 | M | ⬜ | Backend+Mobile |

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
| B10 | Full nutrient tracking (sodium, cholesterol, fiber, sugar, …) | P2 | M | ⬜ | Backend+Mobile |

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
| C10 | Multi-ingredient meal entry (add several at once into a meal slot, not just a recipe) | P2 | M | ⬜ | Backend+Mobile |
| C11 | Repeatable meal templates (group + re-log in one tap) | P2 | M | ⬜ | Backend+Mobile |
| C12 | Recipe import from URL | P2 | M | ⬜ | Backend+Mobile |

## EPIC D — Goals & insights
| ID | Story | Pri | Eff | Status | Track |
|----|-------|-----|-----|--------|-------|
| D1 | Calorie goal + progress ring | P0 | S | ✅ | Backend+Mobile |
| D2 | Macro targets + progress bars | P1 | M | ✅ | Backend+Mobile |
| D3 | History & trends (7/30-day charts) — range-summary endpoint + chart screen | P1 | L | ⬜ | Backend+Mobile |
| D4 | Weekly summary | P2 | M | ⬜ | Backend+Mobile |
| D5 | Streaks / adherence nudges | P2 | M | ⬜ | Mobile |
| D6 | Adaptive goals | P3 | L | ⬜ | Backend |
| D7 | Caloric-needs guide (onboarding calculator) | P1 | M | ⬜ | Backend+Mobile |
| D8 | Suggested meals: re-surface repeat meals + recipes from used ingredients | P2 | L | ⬜ | Backend+Mobile |
| D9 | Favorite foods/ingredients detection (powers D8) | P2 | M | ⬜ | Backend |
| D10 | Weekly meal planning | P3 | L | ⬜ | Backend+Mobile |

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

## EPIC I — Durability & offline
| ID | Story | Pri | Eff | Status | Track |
|----|-------|-----|-----|--------|-------|
| I4 | Offline write queue + idempotent mutations | P1 | L | ⬜ | Mobile+Backend |

## EPIC J — AI vision capture (💤 horizon)
All follow the §7 rule: AI proposes; food DB + user confirm; config-gated.
| ID | Story | Pri | Eff | Status | Track |
|----|-------|-----|-----|--------|-------|
| J1 | Photo of multiple ingredients → list + portions (count/size estimate) | P3 | L | ⬜ | AI+Backend+Mobile |
| J2 | Scan a dish → ingredient breakdown (photo → ingredients + portions) | P3 | L | ⬜ | AI+Backend+Mobile |
| J3 | Scan a dish → quick estimate, "simple mode" (one cal/macro, no breakdown) | P3 | M | ⬜ | AI+Mobile |
| J4 | Recipe from screenshot (vision → structured meal) | P3 | L | ⬜ | AI+Backend+Mobile |
| J5 | Recipe from cookbook page photo (book → meal); also attach a photo of the finished dish | P3 | L | ⬜ | AI+Backend+Mobile |

## EPIC K — Circles & sharing (💤 horizon)
| ID | Story | Pri | Eff | Status | Track |
|----|-------|-----|-----|--------|-------|
| K1 | Link a circle of family/friends (invites, membership) | P3 | L | ⬜ | Backend+Mobile |
| K2 | Portion a meal to circle members (select members + servings; land in their diaries — auto-log vs accept TBD) | P3 | L | ⬜ | Backend+Mobile |
| K3 | Share calorie intake & stats with the circle | P3 | M | ⬜ | Backend+Mobile |
| K4 | Share recipes with circle/users | P3 | M | ⬜ | Backend+Mobile |
| K5 | Coach/clinician shared views | P3 | L | ⬜ | Backend+Mobile |

## EPIC L — Fitness & health
| ID | Story | Pri | Eff | Status | Track |
|----|-------|-----|-----|--------|-------|
| L1 | Weight tracker (manual entry + history) | P2 | M | ⬜ | Backend+Mobile |
| L2 | Water tracking | P2 | S | ⬜ | Backend+Mobile |
| L3 | Activity/fitness tracking that offsets calories (burn) | P3 | L | ⬜ | Backend+Mobile |
| L4 | Health-app integrations: import activity + weight (Health Connect / Apple Health / Google Fit / Fitbit) | P3 | L | ⬜ | Mobile+Backend |

## EPIC M — Modes & experience
| ID | Story | Pri | Eff | Status | Track |
|----|-------|-----|-----|--------|-------|
| M1 | Design pass — visual + UX polish across the app | P1 | M | ⬜ | Mobile |
| M2 | Kids mode (simplified UI + quick, easy-to-prepare kid meals & portion adjustments) | P3 | L | ⬜ | Mobile |

---

### Snapshot
- **Shipped:** Phase 0 + most of the core loop, recipes, meals, macros, Google auth, staging.
- **In flight:** C5 (NL parser implementation).
- **Next P0s:** C4/C6/C7 (NL feature), F4 (prod), E4/E7 (auth decision + disable test flag).
- **New themes captured:** AI vision capture (J), circles & sharing (K), fitness & health (L),
  modes & experience (M) — mostly horizon; D7 (caloric guide) and M1 (design pass) are nearer-term.
- Keep this file honest — flip status as work lands; add stories as they're discovered.
