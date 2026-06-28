# Sitos — Analytics & Instrumentation

**Last updated:** 2026-06-27 · **Companion:** [PRD.md](PRD.md) · [ARCHITECTURE.md](ARCHITECTURE.md) · [BACKLOG.md](BACKLOG.md)
**Status:** Design / taxonomy. The pipeline is not built yet (backlog: *Product analytics /
usage instrumentation pipeline*). **This catalog is the source of truth** — instrument features
against it as you build them.

> **Why this exists:** to measure the product, above all the north-star metric — **weekly logging
> retention** (% of activated users who log on ≥4 of 7 days). It's defined in the PRD but can only
> be *measured* once these events flow.

---

## 1. Principles
1. **Semantic events, not raw clicks.** Log `food_logged { method, meal }`, not `button_tapped`.
2. **You can't backfill.** An event not captured during a period is gone forever — so we
   **instrument as we build** (it's in the Definition of Done), and the retention backbone ships
   before launch.
3. **Own the data.** Events go to our own backend + Postgres (first-party), not a vendor.
4. **Never affect the user.** `track()` is fire-and-forget and offline-tolerant; analytics
   failures are swallowed and never block or slow a user action.
5. **No PII in events.** Use lengths/counts/enums, never raw text, names, or emails (see §8).
6. **This file is the registry.** New events are added here first; don't invent names ad hoc.

## 2. Pipeline (see [ARCHITECTURE.md §7/§10](ARCHITECTURE.md) for the build)
```
Flutter AnalyticsService            ASP.NET Core              Postgres
  track(name, props)                POST /api/events          analytics_event
   → attach standard context        (batch; fire-and-forget;  (append-only, jsonb props;
   → enqueue locally (persisted)     stamps received_ts;       partition by month at scale)
   → batch flush (≈20 evts / 30s /   dedupes on event_id;             │
     on background / on launch)      never 500s the client)    SQL / dashboard / (later) PostHog
```
Foundation shares the **offline write-queue** machinery (backlog I4). Analysis tooling
(dashboards / self-hosted PostHog / A-B flags) comes **later**, once there's traffic.

## 3. Event envelope (every event carries)
| Field | Notes |
|---|---|
| `event_id` | client-generated UUID — server dedupes retries |
| `name` | from the catalog (§6), `object_action` snake_case |
| `props` | jsonb; event-specific, **no PII** |
| `user_id` | authenticated Sitos user id; null pre-login |
| `anon_id` | stable device id; used pre-login, stitched to `user_id` on sign-in |
| `session_id` | see §4 |
| `client_ts` | event time on device |
| `received_ts` | stamped by the server (clock-skew guard) |
| `app_version`, `platform`, `os_version`, `device_model`, `locale`, `network_type` | **standard context**, auto-attached once — never passed per call |

Suggested table:
```sql
analytics_event(
  id uuid primary key,            -- = event_id
  user_id uuid null, anon_id text null,
  session_id text, name text not null,
  props jsonb not null default '{}',
  client_ts timestamptz, received_ts timestamptz default now(),
  app_version text, platform text, os_version text,
  device_model text, locale text, network_type text
);
-- index (name, received_ts) and (user_id, received_ts)
```

## 4. Sessions
A new `session_id` starts on **cold app start** or after **≥30 min** of inactivity. Attached to
every event so funnels and per-session analysis work.

## 5. Naming convention
- Event names: `object_action`, snake_case (`recipe_created`, `food_logged`).
- Prop keys: snake_case; categorical values are **fixed enums** (list them here).
- Prefer counts/lengths/booleans/enums over free text.

## 6. Event catalog

⭐ = **retention backbone** — instrument these before launch; everything else rides along with its
feature.

### Lifecycle
| Event | Props | Notes |
|---|---|---|
| ⭐ `app_open` | `cold: bool` | daily-active signal |
| `screen_view` | `screen` (enum: diary, scan, search, food_detail, recipes, recipe_editor, goal, login) | navigation coverage |

### Logging / core loop
| Event | Props | Notes |
|---|---|---|
| `scan_started` | — | funnel start |
| `scan_succeeded` | `barcode_found: bool` | |
| `scan_failed` | `reason` (no_match, camera_error, canceled) | |
| `manual_barcode_entered` | — | |
| `food_searched` | `query_len: int`, `result_count: int` | **never** log the raw query |
| `food_detail_viewed` | `source` (scan, search, recent, recipe) | |
| ⭐ `food_logged` | `method` (barcode, search, recent, recipe, custom, nl), `meal` (breakfast, lunch, dinner, snacks), `unit` (servings, grams) | **the** retention event |
| `diary_entry_edited` | `field` (quantity, meal) | |
| `diary_entry_deleted` | — | |
| `recent_quick_add_used` | — | |

### Custom foods
| Event | Props | Notes |
|---|---|---|
| `custom_food_created` | `from_scan_miss: bool` | |

### Recipes & NL entry
| Event | Props | Notes |
|---|---|---|
| `recipe_created` | `ingredient_count: int`, `servings: int` | |
| `recipe_edited` | — | |
| `recipe_logged` | `servings: number`, `meal` | |
| `nl_parse_used` | `input_len: int`, `parsed_rows: int`, `accepted_rows: int`, `edited_rows: int` | NL feature success metric (≥60% accepted unedited target) |
| `nl_parse_failed` | `reason` (empty, no_match, ai_unavailable, timeout) | |

### Goals & onboarding
| Event | Props | Notes |
|---|---|---|
| `goal_set` | `has_macros: bool` | |
| `caloric_guide_completed` | `activity_level` | future (D7) |

### Auth & account
| Event | Props | Notes |
|---|---|---|
| `sign_in_succeeded` | `provider` (google, microsoft, apple) | |
| `sign_in_failed` | `reason` | |
| `sign_out` | — | |

### Privacy / settings
| Event | Props | Notes |
|---|---|---|
| `analytics_opt_out_changed` | `enabled: bool` | when off, don't enqueue events |
| `data_export_requested` | — | |
| `account_delete_requested` | — | |

> Future features add their events here in the same change that builds them — e.g. AI vision
> capture (`dish_photo_captured`, `ingredients_photo_parsed`), circles (`circle_meal_shared`),
> health (`weight_logged`, `health_sync_imported`).

## 7. How we answer the product questions

**Which features are used** (adoption, frequency, funnels):
```sql
-- Feature adoption: % of last-28-day actives who created a recipe
with actives as (select distinct user_id from analytics_event
  where name='food_logged' and received_ts > now() - interval '28 days')
select count(distinct e.user_id)::float / nullif((select count(*) from actives),0) as recipe_adoption
from analytics_event e join actives a using (user_id)
where e.name='recipe_created' and e.received_ts > now() - interval '28 days';

-- Scan funnel conversion
select
  count(*) filter (where name='scan_started')   as started,
  count(*) filter (where name='food_logged' and props->>'method'='barcode') as logged
from analytics_event where received_ts > now() - interval '7 days';
```

**North-star — weekly logging retention** (≥4 logging days in a week):
```sql
with logdays as (
  select user_id, date_trunc('week', client_ts) wk, count(distinct client_ts::date) days
  from analytics_event where name='food_logged' group by 1,2)
select wk, count(*) filter (where days>=4)::float / count(*) as weekly_logging_retention
from logdays group by wk order by wk;
```

**Which features drive retention** (the valuable, subtle one):
- Segment cohort retention by **feature adoption in week 1** — e.g. compare 4-week retention of
  users who fired `recipe_created` (or `nl_parse_used`) in their first week vs those who didn't.
- ⚠️ **Correlation, not causation** — power users do more of everything. Use this to form
  hypotheses; prove causation later with **feature flags + A/B** (PostHog or a simple flag system).

## 8. Privacy (Play Store requirement)
- **No PII in `props`** — no emails, names, raw search text, raw NL ingredient text, or notes.
  Use lengths/counts/enums (e.g. `query_len`, not the query).
- Events tie to `user_id`, which is already the user's own data.
- **Opt-out** respected client-side (don't enqueue when off).
- `analytics_event` rows are included in account **export & delete** (backlog E8/E9).
- Disclosed in the Play **Data Safety** form.
- Distinct from **ops/observability** (App Insights — latency/errors, backlog F7); product
  analytics lives in our own queryable store.

## 9. Definition of done hook
Per [PRD §11](PRD.md) and [ARCHITECTURE §9.4](ARCHITECTURE.md): a feature isn't done until its
key user action emits an event **defined here**. Add the event to §6 in the same PR.
