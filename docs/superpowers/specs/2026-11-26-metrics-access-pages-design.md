# Metrics Access page — design

Date: 2026-11-26 · Branch: `metrics-access-pages`

## Intent

Clients and prospects need one public page that answers: **"If I buy plan X, which
metrics do I get, and how far back and how close to now?"** Today `/available_metrics`
is an engineer-facing table (selectors, aggregation, "can mutate") with a single
FREE/RESTRICTED flag, so it cannot answer that. The new page should look like a
product page, not an admin table, and be good enough to send to a prospect.

Built in sanbase (Phoenix LiveView) first. Merging it into the pricing page in the
web app is a possible later step and is out of scope here.

## Goals

- Pick a plan: **Free · Sanbase Pro · Sanbase Max · Business Pro · Business Max**.
- For that plan, every public metric, with two access columns: **In Sanbase** and
  **Via API**. The same plan gives different windows in each (Business Pro: full
  history in Sanbase, 2 years via API).
- Browse by category › group (Categorization taxonomy), or as one flat list ("All").
- Search by metric name or display name.
- Toggle dates: **relative** ("Last 2 years", "30-day lag") vs **absolute** ("Since
  2024-11-26", "Until 2026-10-27"), resolved against today.
- Locked metrics stay visible, greyed, with the lowest of the five plans that
  unlocks them ("Available from Sanbase Max").
- Registry and non-registry (code-defined) metrics appear together, one row each.
- All state in the URL, so sales can send a link to a specific view.

## Non-goals

- Composable bundles / packages, Institutional, Enterprise, API Pro, Basic, Custom.
- Pricing, checkout, or reading which plans are currently for sale (`SaleControls`).
  The plan list is fixed in code.
- Per-asset coverage. A row can link to the existing `/available_metrics/:metric`
  details page, which already shows assets.
- Changing `/available_metrics`. It stays as is.
- Changing any access logic.

## Anti-goals (fails even if it works)

- The page shows a window different from what the API **enforces**. It must be
  computed by the same `AccessChecker` functions enforcement uses, with the plan's
  real subscription product, not by a second hand-written table of plan limits.
  Note: `getAccessRestrictions` (`Restrictions.get_all/2`) passes the product code as
  both requested and subscription product, so for "Sanbase Pro via API" it reports
  the API PRO plan (full, realtime) while enforcement
  (`AccessControl`, subscription product `SANBASE`) gives 1y with a 30-day lag. The
  page follows enforcement; it does not call `get_all`.
- Hidden, deprecated, or internal metrics leak onto a public page.
- It looks like the admin tables (daisyUI cards, dense 12-column grid).

## Constraints

- Public route, no login, in the existing `scope "/", SanbaseWeb` + `:browser`
  pipeline next to `/available_metrics`.
- Must not be heavier than `/available_metrics`. Building the data reads Postgres
  (`Registry.all/0`, `MetricCategoryMapping.list_all/0`) plus in-memory access
  checks, so it is computed once and cached. Data-module tests need registry and
  category fixtures in the test DB.
- Project rules (AGENTS.md): hand-written Tailwind (no daisyUI components),
  `<.icon>`, streams for collections where practical, unique DOM ids, colocated hooks
  only if JS is needed, zero-arity defs parenthesized.

## Approaches considered

- **A. Extend `/available_metrics`** with plan filters and access columns. Cheapest,
  but that page is internal in content and style; making it client-facing fights
  everything on it. Rejected.
- **B. New standalone public LiveView plus a small pure data module. Chosen.**
  Clean client-facing page; data module reuses existing access logic and catalog.
- **C. JSON endpoint + page in the web app.** Better for the later pricing-page merge,
  but the request is to build it in the backend first. Rejected for now; the data
  module in B is the natural thing to expose as JSON later.

## Decided

### Plans

| Label         | `plan_name`    | subscription product |
|---------------|----------------|----------------------|
| Free          | `FREE`         | same as channel (see below) |
| Sanbase Pro   | `PRO`          | `SANBASE`            |
| Sanbase Max   | `MAX`          | `SANBASE`            |
| Business Pro  | `BUSINESS_PRO` | `SANAPI`             |
| Business Max  | `BUSINESS_MAX` | `SANAPI`             |

Channels (= `requested_product`): `SANBASE` ("In Sanbase"), `SANAPI` ("Via API").

**FREE gotcha:** `ApiAccessChecker.historical_data_in_days_sanbase/1` has no `FREE`
clause, so FREE must be evaluated with `subscription_product == requested_product`.

Expected headline windows today (from the checker modules; the page computes them,
this is only for sanity checks):

| Plan          | In Sanbase              | Via API                 |
|---------------|-------------------------|-------------------------|
| Free          | 2y history, 30-day lag  | 1y history, 30-day lag  |
| Sanbase Pro   | full, realtime          | 1y, 30-day lag          |
| Sanbase Max   | full, realtime          | 2y, realtime            |
| Business Pro  | full, realtime          | 2y, realtime            |
| Business Max  | full, realtime          | full, realtime          |

Per metric on top of that: metrics free in `access_map` have no window at all (or
only historical / only realtime free); metrics with a min plan (`pro`/`max`, set per
product) are locked below it. Note `max_plan?("SANBASE", "BUSINESS_PRO")` is false,
so Business Pro is locked out of Max-only metrics in Sanbase. The page shows that as
is; it is current behavior, not something this work changes.

### Data module — `Sanbase.Billing.PlanMetricAccess` (name adjustable)

Read-only (DB reads, no writes). Builds one cached structure:

1. **Metric universe:** `Sanbase.Metric.available_metrics()` — union of registry and
   code-defined metrics, hidden metrics already removed. Anything not in this list
   never appears.
2. **Rows:** catalog entries do not carry `is_deprecated` or variant names, so use
   raw `Registry.all/0` rows with `Registry.resolve_registry/1` for registry metrics;
   universe names not in any registry row are code-defined rows. Status and
   deprecation come from `Sanbase.Metric.metadata/1` for both kinds. Categories come
   from `Sanbase.AvailableMetrics.metric_to_categories_map/0` (made public), keyed by
   public metric name — the same source `/available_metrics` uses.
   A registry template (e.g. `mvrv_usd_{{timebound}}`) is one row whose variants are
   its resolved names that are in the universe; a code metric is one row.
   Display name: registry `human_readable_name`; for templates it still contains
   `{{…}}` placeholders, which must never be shown raw (strip them or render the
   parameter as a muted chip, builder's call). Technical name shown secondary.
   Drop: registry rows with `is_deprecated: true`; code metrics whose metadata marks
   them deprecated; rows with no variant left in the universe.
   Alpha/beta metrics (`status in ["alpha", "beta"]`, blocked for normal users by
   `AccessControl`): **excluded** for now — only `released` metrics are shown. May
   be revisited later (e.g. a "Beta" badge).
3. **Taxonomy:** categories/groups from `MetricCategoryMapping` joined via
   `Catalog.entry_key/1`, ordered by category and group display order
   (`MetricCategory.list_ordered/0`, group order). Drop rows whose every group is in
   `AvailableMetrics.hidden_group_names()` ("Deprecated", "Internal Metrics").
   Uncategorized rows go under a final **"Other"** category.
4. **Access:** for every variant × 5 plans × 2 channels, using `AccessChecker`
   (exactly the calls `Restrictions.get/6` makes):
   - `plan_has_access?/4` false → `{:locked, min_plan}` where `min_plan` is the
     lowest of the five plans for which it is true;
   - `restricted?/1` false → `:free`;
   - otherwise `{:window, history_days | nil, lag_days | nil}` from
     `historical_data_in_days/6` and `realtime_data_cut_off_in_days/5`
     (`0` lag normalized to `nil`).
   Store **days, not datetimes**, so the cache is never stale; dates are resolved at
   render.
   Access is computed for **every** variant (cheap). Variants of a registry row with
   identical access collapse into one row; if a row's variants diverge (should not
   happen, since access and min plan live once per registry row, but prod registry
   can drift from seeds), each distinct access forms its own row. No "varies" UI and
   no silent first-variant answer.
   For FREE, the subscription product is the channel itself (see the FREE gotcha).
   For the other plans it is the product in the plans table — matching enforcement.
5. **Cache:** `Sanbase.Cache.RehydratingCache` (stale-while-revalidate, already used
   by `project_metrics_resolver.ex:236-262`): refresh ~10 min, TTL 1 h, so visitors
   never wait on a rebuild. If the first hydration has not finished, compute
   synchronously. Variant × plan × channel ≈ 2k × 10 ≈ 20k in-memory calls.

### Page — `SanbaseWeb.MetricsAccessLive` at `/metrics_access` (path adjustable)

```
 Santiment metrics by plan                                  Dates: (Relative | Exact)
 [Free] [Sanbase Pro] [Sanbase Max] [Business Pro ✓] [Business Max]
 ┌ Business Pro ─────────────────────────────────────────────────────┐
 │ In Sanbase: full history · realtime   Via API: last 2 years · realtime │
 │ 1,180 metrics included · 60 need Business Max / Sanbase Max          │
 └────────────────────────────────────────────────────────────────────┘
 Categories        │ 🔍 Search metrics…
  All       1,240  │ On-chain › Exchange flows
  Market      140  │  Exchange Inflow      exchange_inflow      Full history      Since 2024-11-26
  On-chain ◀  610  │  MVRV  +6 variants    mvrv_usd_{…}         Full history      Since 2024-11-26
  Social      190  │  Whale Transactions   whale_txs            🔒 Sanbase Max    🔒 Business Max
  Other        40  │
```

- Plan cards: plan name and both headline windows. Selected state obvious. Business
  Pro says "Includes Sanbase Pro", Business Max "Includes Sanbase Max" (that is why
  Business Pro shows Max-only metrics locked in Sanbase).
- Rows are not kept in the LiveView process; they are read from cache on each
  `handle_params`. The list is paginated: the first 150 items, then more appended on
  scroll (`phx-viewport-bottom`) with a "Show more" button as fallback.
- Summary strip: counts **per channel** ("In Sanbase: 1,180 of 1,240 · Via API:
  1,100 of 1,240"), since a metric can be open in one and locked in the other.
- Locking is per cell: a cell locked in one channel shows the lock there only; the
  whole row is greyed only when locked in both channels.
- Left rail: categories with counts ("All" = every category in order, still with
  `Category › Group` headers); collapses to a select on mobile.
- Search also matches variant names; matching variants are listed inline under the
  row, not hidden in a closed `<details>`.
- Table: display name, technical name (monospace, muted), In Sanbase cell, Via API
  cell. Cells render `:free` as "Free · full access", windows per the date toggle,
  locked as greyed row + lock + "Available from …". Optional link to
  `/available_metrics/:metric`.
- URL params: `plan` (default `free` — the baseline everyone has; switching up shows
  what unlocks), `category`, `q`,
  `dates=relative|exact`. Defaults left out of the query string, same convention as
  `/available_metrics`.
- Polish: smooth transitions on plan switch, hover states, sticky header and rail,
  readable at mobile width, empty state for searches.

## Part 2 — fix `getAccessRestrictions` own-plan answer (separate commit)

Bug: with no `plan`/`planName` argument (caller's own plan),
`AccessControlResolver.restrictions_subject/2` resolves a single product code
(requested product, falling back to subscription product) and
`Restrictions.get_all/5` uses it as both requested and subscription product.
Enforcement (`AccessControl.context_to_plan_name_product_code/1`) and
`getMetric { metadata }` (`MetricResolver.get_metadata/3`) keep them separate.
Effect: a Sanbase PRO/BASIC subscriber calling from the API is told full history +
realtime (API PRO/BASIC stats) while enforcement gives 1y + 30-day lag.
`SignalResolver` (`resolution_to_signal_restrictions/1`,
`resolution_to_all_signals_restrictions/1`) has the same collapse.

Named-plan calls are not a bug: there `product` means the plan's own product, so
`plan: PRO, product: SANAPI` is the API PRO plan and its answer is correct. Not
expressible today: "Sanbase PRO used via API" — not added now.

Fix:
- `Restrictions.get_all` takes `subscription_product` separately (default = product
  code, so named-plan behavior and other callers are unchanged).
- Own-plan path passes the context's subscription product; named-plan path keeps
  `product` for both.
- Subscription product added to the `Cache.wrap` key.
- `SignalResolver` passes the context subscription product.
- Tests: Sanbase PRO subscriber on an API request → 1y / 30d lag; named-plan
  answers unchanged; signal restrictions follow the same rule.

## Left to the builder

- Exact module/route names, component split, styling details within the above.
- Whether the table uses streams or a plain comprehension (the list is bounded and
  re-rendered on filter change; pick what keeps diffs small).
- Wording of relative windows ("Last 2 years" vs "730 days").
- Tests: unit tests for the data module (plan × channel matrix on a few known
  free / restricted / min-plan metrics, FREE gotcha, variant collapsing, hidden and
  deprecated exclusion) and LiveView tests for plan switch, category filter, search,
  date toggle, and locked rendering, using DOM ids.
- Run `mix precommit` at the end. No commits — Ivan commits.
