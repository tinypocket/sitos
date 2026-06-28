# Sitos — Design Needs (designer handoff brief)

**Last updated:** 2026-06-27 · **For:** product designer (UX + visual)
**Context docs:** [PRD.md](PRD.md) (product) · [ROADMAP.md](ROADMAP.md) (priorities) · [ARCHITECTURE.md](ARCHITECTURE.md) (how it's built) · [ANALYTICS.md](ANALYTICS.md)

> One ask above all: **make the "entry experience" — every way food gets *into* the app — fast,
> delightful, and trustworthy.** That's the heart of the product and what we're building next.

---

## 1. What Sitos is
A calorie & macro tracker. Core loop: **scan a barcode → instant nutrition → log it to a daily
diary** (target: under 5 seconds from app open). Beyond barcodes, you can search, quick-add
recents, build **recipes / split a meal across a family**, set goals, and — coming next — add
ingredients by **typing/dictating a list** or **snapping a photo**.

- **Platform:** Android first (Flutter, **Material 3**), iOS later from the same codebase.
- **Audience:** habitual daily trackers; home cooks/families; data-conscious users who want to
  trust the numbers. Logging usually happens **one-handed, on the go, often in a kitchen or a
  store aisle.**

## 2. Design principles (please design to these)
1. **Speed beats breadth.** The fastest path (scan → log) must be one or two taps; never bury it.
2. **Glanceable & motivating.** The diary should answer "am I under my goal today?" at a glance.
3. **Trust through honesty.** AI/automated features **propose**; the user **confirms**. We never
   silently guess nutrition — so we need a clear, consistent visual language for **confidence**
   ("we're sure" vs "please check this") that's honest without being alarming.
4. **Low friction.** Quantities/portions are the #1 friction point — make them effortless.
5. **Degrade gracefully.** Every screen needs **loading / empty / error / offline** states; a
   missing feature should look intentional, not broken.
6. **One-handed, thumb-reachable** primary actions.
7. **Distinctive, not generic.** Please avoid stock "AI app" aesthetics (purple gradients, Inter-
   on-white). It's a health/data product — should feel trustworthy *and* have character.

## 3. What exists today (starting point — basic, built by engineers)
Functional but unstyled beyond Material 3 defaults. Current screens:

| Screen | State today |
|---|---|
| **Splash / Login** | Green background, white "S" wordmark, "Sitos", tagline "Scan. Log. Track.", Google sign-in button |
| **Diary (home)** | Calorie ring vs goal, macro progress bars, meals grouped (Breakfast/Lunch/Dinner/Snacks) with subtotals, a "recent foods" quick-add strip, app-bar icons (recipes, goals, sign-out) |
| **Scan** | Camera barcode scanner |
| **Food detail / add** | Nutrition + quantity (servings/grams) + meal picker → adds to diary |
| **Search** | Text search of foods |
| **Recipes** | List; create/edit; log N servings to a meal |
| **Recipe editor** | Name, servings, ingredient picker, per-ingredient quantity |
| **Goal** | Daily calorie target + optional protein/carb/fat targets |

- **Current visual:** Material 3, single green seed color (`#2E7D32`), system fonts. No dark mode,
  no custom component system, minimal empty/error states, basic app icon & splash.
- **Tech constraint for handoff:** it's Flutter/Material 3 — design tokens should map cleanly to a
  Flutter `ThemeData` (color scheme, type scale, shape, elevation). Favor patterns that also adapt
  to iOS later.

## 4. Priority 1 — The entry experience  ⭐ (design this first)

The strategic shape: **every input method converges on one shared flow** —
**capture → resolve to real foods → review & confirm → commit.** Design that flow once and it's
reused by typing, photos, and URLs. Pieces:

| # | Ask | Goal & key states |
|---|---|---|
| **E1** | **The "Add" entry point** | From the diary, how does the user start adding food? It must make the **primary path (scan) one tap** while surfacing the other methods (search, recent, **type/dictate**, **photo**, **paste URL**) without clutter. Likely a FAB → bottom sheet, but that's your call. Thumb-reachable. |
| **E2** | **Shared "review & confirm" surface (the keystone)** | A list of **proposed rows**: matched food (name/brand), **quantity + unit**, calories, and a **confidence indicator**. User can edit a match, change quantity, remove, or add a row, then **commit to a meal slot or a recipe**. Must be **input-agnostic** (same surface for typed text, photos, URLs). States: all-confident · some-low-confidence (flagged for attention) · no-match rows · still-parsing/loading · empty. |
| **E3** | **Smart Add (natural language)** | Input where the user types **or dictates** "5 eggs, 2 tbsp oil, some salt, half a cup of cottage cheese". Show the in-progress parsing state, then hand off to E2. Voice affordance matters (hands-busy cooking). |
| **E4** | **Photo capture (vision)** | Camera / photo-picker flows for: (a) **loose ingredients** → list + portions (e.g. "3 medium cucumbers"), (b) **a dish** → either a full **ingredient breakdown** or a quick **"simple mode" calorie estimate** (let the user choose). Capture UI → processing → E2. |
| **E5** | **Multi-ingredient meal entry + repeatable meal templates** | Add several ingredients at once into a **meal slot** (lunch/dinner). Save a group as a **named, reusable meal** that re-logs in **one tap** (a key retention moment — design that "log my usual" interaction to feel great). |
| **E6** | **Quantity / portion editor** | The recurring friction point. Fast switching between **servings and grams**, plus **count + size** ("3 medium…"). Make it a delight, not a number-pad chore. |

## 5. Priority 2 — Onboarding & first run
| # | Ask | Notes |
|---|---|---|
| **O1** | **First-run onboarding** | Sign in → **caloric-needs guide** (age/sex/height/weight/activity → a suggested daily target) → confirm goal → guide to a **first successful log** (the activation moment). Keep it short; let users skip. |
| **O2** | **Empty states** | Empty diary, no recipes, no recents — treat these as friendly onboarding/teaching moments, not dead ends. |

## 6. Priority 3 — Design pass on core screens + a visual system (backlog M1)
| # | Ask | Notes |
|---|---|---|
| **V1** | **Visual system / design tokens** | Color (incl. **dark mode**), type scale, spacing, shape, elevation, iconography, motion/micro-interactions. Deliver as reusable tokens mappable to Flutter `ThemeData`. |
| **V2** | **Component library** | Buttons, chips (incl. the **confidence chip**), cards, list rows, bottom sheets, the **calorie ring**, **macro progress bars**, segmented controls, number/portion picker, loading skeletons, snackbars. |
| **V3** | **Diary / home redesign** | Most-seen screen — glanceable, motivating, with the Add entry point and meal grouping. |
| **V4** | **Polish the rest** | Food detail, search, scan overlay, recipes, recipe editor, goal — consistent with the system. |
| **V5** | **App identity** | Refine logo/wordmark, **app icon**, splash, and overall color/brand direction (currently a single green; explore if you think it helps). |

## 7. Cross-cutting requirements (apply to everything)
- **States:** loading / empty / error / offline / success for every screen.
- **Confidence as a first-class UI concept** — one consistent treatment everywhere AI proposes
  something (chips? color? icon + label?). Honest but calm.
- **Accessibility:** WCAG AA contrast, dynamic type, ≥48dp targets, screen-reader labels,
  one-handed reach for primary actions.
- **Light + dark** themes.
- **Perceived speed:** optimistic UI, skeletons, instant feedback (supports the <5s promise).
- **Platform:** Material 3 now; choose patterns that adapt to iOS later.

## 8. Horizon (design *thinking* welcome, not pixel-final yet)
So the system stays extensible — these are coming: **history & trends charts** (7/30-day, weekly
summary), **weekly meal planning**, **circles** (share a meal/portion it out to family/friends;
share intake & stats), **weight & water tracking**, **nutrient detail** (sodium, cholesterol…),
and a **kids mode** (simpler, quick-meal-focused). Don't design these now — just keep them in mind.

## 9. Deliverables & format
- **Figma**: design tokens/styles + component library; the **entry-experience flow end-to-end**
  (E1–E6) as the priority; onboarding; core screens; **all states**; **light + dark**.
- An **interactive prototype** of the entry flow (scan, smart-add, and photo paths into the shared
  review surface).
- **Redlines / specs** suitable for Flutter handoff (spacing, sizes, tokens).

## 10. Open questions for you (and us)
1. **Add entry point** pattern — FAB + sheet, a dedicated tab, or something else?
2. How prominent should each input method be? Scan is the hero; how do we surface **smart-add /
   photo / URL** without burying it or cluttering?
3. **Confidence visualization** — what reads as "please check this" without feeling like an error?
4. **Brand direction** — keep/evolve the green? Tone: warm & encouraging vs clean & precise (or a
   blend)? Distinctive but trustworthy for a health/data app.
5. **Voice/dictation** affordance and feedback.

*Engineering note for context (not a design constraint):* features are built so AI only proposes
structure/estimates — the database and the user are the source of truth for nutrition. The
**confidence + review/confirm** UI is what makes that trustworthy, so it's the most important
thing to get right.
