# Metrics Access Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A public, no-login LiveView at `/metrics_access` showing, per plan (Free, Sanbase Pro, Sanbase Max, Business Pro, Business Max), every released public metric by category with its access window In Sanbase and Via API; plus a fix so `getAccessRestrictions` (own plan) and signal restrictions use the caller's real subscription product.

**Architecture:** A read-only data module `Sanbase.Billing.Plan.PlanMetricAccess` builds a cached list of rows (one per registry row or code metric) with access per plan × channel computed by `Sanbase.Billing.Plan.AccessChecker` — the same functions enforcement uses. A pure formatting module turns access values into labels (relative or exact dates). `SanbaseWeb.MetricsAccessLive` renders it with URL-driven state and streams.

**Tech Stack:** Elixir, Phoenix LiveView, Tailwind (hand-written, no daisyUI components), ExUnit + `Phoenix.LiveViewTest`.

**Spec:** `docs/superpowers/specs/2026-11-26-metrics-access-pages-design.md`

## Global Constraints

- **No commits, no pushes.** Each task ends by leaving changes in the working tree with a suggested commit message; Ivan commits. Task 1 must be committable on its own (bug fix), separate from Tasks 2–5.
- **DB safety:** before any `mix test`, confirm `MIX_ENV` is not `prod` and `DATABASE_URL` is unset (`echo "$MIX_ENV $DATABASE_URL"`). Never boot the app against a non-local DB.
- Zero-arity defs always parenthesized: `def plans() do`, `defp foo(), do: ...`.
- Plans, in this order, with these exact labels / plan names / subscription products:
  `free` "Free" `FREE` (channel's own product) · `sanbase_pro` "Sanbase Pro" `PRO` `SANBASE` · `sanbase_max` "Sanbase Max" `MAX` `SANBASE` · `business_pro` "Business Pro" `BUSINESS_PRO` `SANAPI` · `business_max` "Business Max" `BUSINESS_MAX` `SANAPI`.
- Channels: `:sanbase` → requested product `"SANBASE"`, label "In Sanbase"; `:api` → `"SANAPI"`, label "Via API".
- Only metrics in `Sanbase.Metric.available_metrics()` with metadata `status == "released"` and `is_deprecated == false` appear; registry rows with `is_deprecated: true` never appear; rows whose every group is in `Sanbase.AvailableMetrics.hidden_group_names()` never appear.
- Raw `{{…}}` template placeholders never appear in a display name.
- Route: `live("/metrics_access", MetricsAccessLive)` in the existing public `scope "/", SanbaseWeb` / `pipe_through([:browser])` block next to `/available_metrics` (`lib/sanbase_web/router.ex:473-481`). No login.
- URL params: `plan` (default `free`), `category` (default all), `q`, `dates` (`relative` default | `exact`). Defaults are omitted from the URL; unknown values fall back to defaults.
- UI: hand-written Tailwind utilities; daisyUI *color tokens* (`bg-base-100`, `text-base-content/60`, `primary`) are fine so the theme/dark mode works, daisyUI *component classes* (`btn`, `card`, `select`, `dropdown`, `badge`) are not. `<.icon name="hero-…">` for icons. Unique DOM ids on key elements.
- `/available_metrics` behavior unchanged.
- Run `mix precommit` at the end and fix what it reports.

- Tests name `mvrv_usd` as "a restricted metric with min plan FREE on both products". Before relying on it, check its seeded `access`/`min_plan` (`lib/sanbase/clickhouse/metric/metric_files/available_v2_metrics.json:360`); if it differs, use any metric that matches that description.

## Review Focus

1. A metric in the universe whose `Sanbase.Metric.metadata/1` returns `{:error, _}` → skipped, page still renders. (Task 3 test)
2. A metric no listed plan unlocks in a channel (min plan `CUSTOM`) → `{:locked, nil}` → "Custom plan only", no crash. (Task 2 + Task 4 tests)
3. Search with regex characters (`(`, `*`, `[`) or matching nothing → literal substring match / empty state, no crash. (Task 5 test)
4. Bogus URL params (`plan=bogus&category=nope&dates=foo`) → defaults, page renders. (Task 5 test)
5. Template registry names (`… {{timebound}}`) and `nil` human-readable names → clean display name, falls back to metric name. (Task 3 test)

---

### Task 1: Own-plan restrictions use the subscription product (bug fix, standalone)

**Files:**
- Modify: `lib/sanbase/billing/plan/standard_access_checker/api_access_checker.ex:104-111, 136-143` (add `"FREE"` clauses)
- Modify: `lib/sanbase/billing/plan/restrictions.ex:91-110` (`get_all`)
- Modify: `lib/sanbase_web/graphql/resolvers/access_control_resolver.ex:13-89`
- Modify: `lib/sanbase_web/graphql/resolvers/signal_resolver.ex:157-183`
- Test: `test/sanbase_web/graphql/access_restrictions_test.exs`, `test/sanbase/billing/plan/restrictions_subscription_product_test.exs` (new)

**Interfaces:**
- Produces: `Restrictions.get_all(plan_name, product_code, filter \\ nil, entitlement \\ nil, grant \\ nil, subscription_product \\ nil)` — `nil` subscription product means "same as `product_code`" (today's behavior).

- [ ] **Step 1: Write failing tests**

`test/sanbase/billing/plan/restrictions_subscription_product_test.exs` (`use Sanbase.DataCase, async: true`):

```elixir
test "FREE with a SANBASE subscription product answers like API FREE" do
  assert ApiAccessChecker.historical_data_in_days("SANBASE", "FREE") == 365
  assert ApiAccessChecker.realtime_data_cut_off_in_days("SANBASE", "FREE") == 30
end

test "every plan name a SANBASE subscription can carry has a clause" do
  for plan <- ["FREE", "BASIC", "PRO", "PRO_PLUS", "MAX"] do
    ApiAccessChecker.historical_data_in_days("SANBASE", plan)
    ApiAccessChecker.realtime_data_cut_off_in_days("SANBASE", plan)
  end
end

test "get_all keeps today's answer when no subscription product is given" do
  r = Restrictions.get_all("PRO", "SANAPI", :metric) |> Enum.find(&(&1.name == "mvrv_usd"))
  assert r.restricted_from == nil and r.restricted_to == nil
end

test "Sanbase PRO via API: 1y history and 30-day lag" do
  r =
    Restrictions.get_all("PRO", "SANAPI", :metric, nil, nil, "SANBASE")
    |> Enum.find(&(&1.name == "mvrv_usd"))

  assert_in_delta DateTime.diff(DateTime.utc_now(), r.restricted_from, :day), 365, 1
  assert_in_delta DateTime.diff(DateTime.utc_now(), r.restricted_to, :day), 30, 1
end
```

In `access_restrictions_test.exs`, add (pattern: `Sanbase.Accounts.Apikey.generate_apikey/1` + `setup_apikey_auth/2`, see `test/sanbase_web/plans/business_plans_test.exs:19`):

```elixir
test "sanbase pro user calling with an apikey gets the API window enforcement applies", %{user: user} do
  insert(:subscription_pro_sanbase, user: user)
  {:ok, apikey} = Sanbase.Accounts.Apikey.generate_apikey(user)
  conn = setup_apikey_auth(build_conn(), apikey)

  r = get_access_restrictions(conn) |> Enum.find(&(&1["name"] == "mvrv_usd"))
  # 1 year history, 30-day realtime cut-off
  assert iso_datetime_newer_than_days(r["restrictedFrom"], 366)   # helper: write inline if absent
  assert iso_datetime_older_than_days(r["restrictedTo"], 29)
end

test "named plan answers are unchanged: plan: PRO, product: SANAPI is API PRO", %{conn: conn} do
  # restrictedFrom nil and restrictedTo nil for mvrv_usd
end
```

Also add a signal case in `test/sanbase_web/graphql/` (find the existing signal restrictions test with `grep -rln "restrictedFrom" test | xargs grep -l signal`) asserting a Sanbase PRO apikey caller gets a non-nil `restrictedTo` for a restricted signal.

- [ ] **Step 2: Run — expect failures** (`FunctionClauseError`/`CaseClauseError` for FREE; wrong windows for the apikey case)

Run: `mix test test/sanbase/billing/plan/restrictions_subscription_product_test.exs test/sanbase_web/graphql/access_restrictions_test.exs`

- [ ] **Step 3: Implement**
  - `ApiAccessChecker.historical_data_in_days_sanbase/1` and `realtime_data_cut_off_in_days_sanbase/1`: add `"FREE" -> @free_plan_stats[...]`.
  - `Restrictions.get_all/6`: new last arg; pass `subscription_product || product_code` as the subscription product to `get/6`. `get_extra_queries/2` unchanged.
  - `AccessControlResolver.restrictions_subject/2`: also return `subscription_product` — `nil` when `asked_for_another_plan?`, else `context[:subscription_product]` (a product code or `nil`; the same key `SignalResolver` and `MetricResolver.get_metadata/3` use). Pass it to `get_all` and append it to the `Cache.wrap` key tuple.
  - `SignalResolver`: pass `context[:subscription_product]` as the subscription product in `Restrictions.get/5` and as the new arg in `get_all`.

- [ ] **Step 4: Run — expect PASS**, plus the full existing suites: `mix test test/sanbase_web/graphql/access_restrictions_test.exs test/sanbase/billing test/sanbase_web/graphql/billing test/sanbase_web/plans`

- [ ] **Step 5: Stop for Ivan.** Suggested message: `Use the subscription product in own-plan access restrictions`

---

### Task 2: Plan × channel access for one metric (pure)

**Files:**
- Create: `lib/sanbase/billing/plan/plan_metric_access.ex`
- Test: `test/sanbase/billing/plan/plan_metric_access_test.exs`

**Interfaces:**
- Produces:
  - `@type plan_key :: String.t()` (`"free" | "sanbase_pro" | "sanbase_max" | "business_pro" | "business_max"`)
  - `@type channel :: :sanbase | :api`
  - `@type access :: :free | {:window, history_days :: pos_integer() | nil, lag_days :: pos_integer() | nil} | {:locked, min_plan_key :: plan_key() | nil}`
  - `plans() :: [%{key: plan_key, label: String.t(), plan_name: String.t(), subscription_product: String.t() | nil}]` (order per Global Constraints)
  - `channels() :: [%{key: channel, label: String.t(), product: String.t()}]`
  - `access(query_or_argument :: {:metric, String.t()}, plan_key, channel) :: access`
  - `headline(plan_key, channel) :: {history_days | nil, lag_days | nil}`

- [ ] **Step 1: Write failing tests** (`use Sanbase.DataCase, async: false`; set min plans by updating a seeded registry row + `Sanbase.Metric.Registry.refresh_stored_terms()`, as `test/sanbase_web/graphql/access_restrictions_test.exs:28-31` does):

```elixir
test "headline windows match the checker modules" do
  assert PlanMetricAccess.headline("free", :sanbase) == {730, 30}
  assert PlanMetricAccess.headline("free", :api) == {365, 30}
  assert PlanMetricAccess.headline("sanbase_pro", :sanbase) == {nil, nil}
  assert PlanMetricAccess.headline("sanbase_pro", :api) == {365, 30}
  assert PlanMetricAccess.headline("sanbase_max", :api) == {730, nil}
  assert PlanMetricAccess.headline("business_pro", :sanbase) == {nil, nil}
  assert PlanMetricAccess.headline("business_pro", :api) == {730, nil}
  assert PlanMetricAccess.headline("business_max", :api) == {nil, nil}
end

test "a free metric is :free on every plan and channel"            # pick from Sanbase.Metric.free_metrics()
test "a restricted metric gets the plan window"                     # mvrv_usd: business_pro/:api == {:window, 730, nil}
test "a max-only metric is locked below max, with the lowest unlocking plan"
  # set mvrv_usd sanbase_min_plan "max", sanapi_min_plan "max"
  # access(m, "sanbase_pro", :sanbase) == {:locked, "sanbase_max"}
  # access(m, "business_pro", :sanbase) == {:locked, "sanbase_max"}   # max_plan?("SANBASE","BUSINESS_PRO") is false
  # access(m, "business_pro", :api) == {:locked, "business_max"}
test "a metric no listed plan unlocks is {:locked, nil}"           # min plan CUSTOM (Review Focus 2)
```

- [ ] **Step 2: Run — expect FAIL** (`PlanMetricAccess` undefined). `mix test test/sanbase/billing/plan/plan_metric_access_test.exs`

- [ ] **Step 3: Implement** `access/3` with `AccessChecker.plan_has_access?/4` → `restricted?/1` → `historical_data_in_days/6` + `realtime_data_cut_off_in_days/5` (lag `0` → `nil`). Subscription product: the plan's, or the channel's product for `free`. Lowest unlocking plan = first of `plans()` for which `plan_has_access?` is true in that channel. `headline/2` calls `ApiAccessChecker`/`SanbaseAccessChecker` `.historical_data_in_days/2` and `.realtime_data_cut_off_in_days/2` with (subscription product, plan name) — no hand-written numbers.

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Stop for Ivan.** Suggested message: `Add PlanMetricAccess plan x channel access`

---

### Task 3: Rows — universe, grouping, taxonomy, cache

**Files:**
- Modify: `lib/sanbase/available_metrics/available_metrics.ex:330` — make `metric_to_categories_map/0` public (`def metric_to_categories_map() do`, with `@doc`).
- Modify: `lib/sanbase/billing/plan/plan_metric_access.ex`
- Test: `test/sanbase/billing/plan/plan_metric_access_test.exs`

**Interfaces:**
- Consumes: `access/3`, `plans/0`, `channels/0` (Task 2); `Sanbase.AvailableMetrics.metric_to_categories_map/0`, `sort_by_taxonomy/1`, `taxonomy_placement/1`.
- Produces:
  - `@type row :: %{id: String.t(), name: String.t(), metrics: [String.t()], category: String.t(), group: String.t() | nil, categories: list(), access: %{{plan_key, channel} => access}}` — `id` is `"r-<registry id>"` (or `"r-<registry id>-<first metric>"` when that registry row was split by diverging access) or `"m-<metric>"`; `metrics` sorted; `category` is `"Other"` when uncategorized.
  - `compute_rows() :: [row]` (uncached, taxonomy order). Tests call this directly, never `rows/0`, so cached rows cannot leak between tests that mutate the registry.
  - `rows() :: [row]` — `Sanbase.Cache.RehydratingCache.register_function(&compute_rows/0 wrapped to return {:ok, rows}, {__MODULE__, :rows}, ttl 3600, refresh ~600)` once, then `RehydratingCache.get/3`; on `{:error, _}`/`{:nocache, _}`/timeout before first hydration, fall back to `compute_rows()` synchronously. Follow `project_metrics_resolver.ex:236-262` (register can exit on timeout — catch it).

- [ ] **Step 1: Write failing tests** (map test metrics into a test category like `test/sanbase_web/live/available_metrics_live_test.exs:26-60` does):

```elixir
test "registry template variants collapse into one row with a clean name"   # Review Focus 5: no "{{" in row.name
test "code-defined metrics appear as their own rows"                       # price_usd, id "m-price_usd"
test "alpha/beta, deprecated and hidden metrics are excluded"              # update a registry row status "beta" / is_deprecated true
test "metrics only in a hidden group are excluded"                         # map into group "Internal Metrics"
test "uncategorized rows land under Other, after categorized rows"
test "a metric whose metadata errors is skipped"                           # Review Focus 1: Mock Sanbase.Metric.metadata/1 for one name (use `mock`, see existing usages)
test "variants with diverging access split into separate rows with unique ids"  # mock access for one variant; ids unique across all rows
test "on seeded data, every row id is unique and no registry row is split"     # Enum.uniq_by(rows, & &1.id) == rows; drift canary
test "compute_rows stays fast"                                                 # {us, _} = :timer.tc(&compute_rows/0); assert us < 2_000_000 (ConCache/RehydratingCache headroom)
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement `compute_rows/0`**
  - Universe: `Sanbase.Metric.available_metrics()` filtered by `Sanbase.Metric.metadata/1` (`{:ok, %{status: "released", is_deprecated: false}}`; anything else dropped).
  - Registry index: `Sanbase.Metric.Registry.all()` rejecting `is_deprecated`, each `resolve_registry/1` → `name => registry`. Universe names in it group by registry id; others are code rows.
  - Name: registry `human_readable_name` with `{{…}}` placeholders and leftover separators/whitespace removed; code rows `Sanbase.Metric.human_readable_name/1`; fall back to the metric name when blank/`nil`/error.
  - Categories: union of `metric_to_categories_map()` entries for the row's metrics; reject the row when non-empty and every entry's `group_name` is hidden; `taxonomy_placement/1` gives `category` (nil → `"Other"`) and `group`.
  - Access: `access({:metric, metric}, plan, channel)` for every variant × plan × channel; within a registry row, group variants by their access map — one group → one row, several → one row per group.
  - Order: `sort_by_taxonomy/1` (needs `:metric` and `:categories` keys — set `metric: hd(metrics)`).

- [ ] **Step 4: Run — expect PASS**; also `mix test test/sanbase_web/live/available_metrics_live_test.exs test/sanbase/available_metrics` (public-ized function unchanged).

- [ ] **Step 5: Stop for Ivan.** Suggested message: `Build cached metric rows for plan access page`

---

### Task 4: Labels (pure formatting)

**Files:**
- Create: `lib/sanbase_web/live/metrics_access/metrics_access_format.ex` (`SanbaseWeb.MetricsAccessFormat`)
- Test: `test/sanbase_web/live/metrics_access_format_test.exs`

**Interfaces:**
- Consumes: `access` type, `plans/0` (Task 2).
- Produces: `history(days | nil, :relative | :exact, Date.t()) :: String.t()`, `lag(days | nil, mode, Date.t()) :: String.t()`, `locked(min_plan_key | nil) :: String.t()`.

- [ ] **Step 1: Write failing tests** (today = `~D[2026-11-26]`):

```elixir
assert history(nil, :relative, today) == "Full history"
assert history(nil, :exact, today) == "Full history"
assert history(730, :relative, today) == "Last 2 years"
assert history(365, :relative, today) == "Last year"
assert history(90, :relative, today) == "Last 90 days"
assert history(730, :exact, today) == "Since 2024-11-26"
assert lag(nil, :relative, today) == "Realtime"
assert lag(30, :relative, today) == "30-day delay"
assert lag(30, :exact, today) == "Until 2026-10-27"
assert locked("sanbase_max") == "Requires Sanbase Max"
assert locked(nil) == "Custom plan only"          # Review Focus 2
```

- [ ] **Step 2: Run — expect FAIL**. **Step 3: Implement** (whole years when `rem(days, 365) == 0`, else days; `Date.add(today, -days)` ISO). **Step 4: Run — expect PASS.**

- [ ] **Step 5: Stop for Ivan.** Suggested message: `Add access label formatting`

---

### Task 5: The page

**Files:**
- Create: `lib/sanbase_web/live/metrics_access/metrics_access_live.ex` (`SanbaseWeb.MetricsAccessLive`)
- Create: `lib/sanbase_web/live/metrics_access/metrics_access_components.ex` (`SanbaseWeb.MetricsAccessComponents`: `plan_picker/1`, `plan_summary/1`, `category_rail/1`, `access_cell/1`, `date_toggle/1`)
- Modify: `lib/sanbase_web/router.ex:477` (add the route)
- Test: `test/sanbase_web/live/metrics_access_live_test.exs`

**Interfaces:**
- Consumes: `PlanMetricAccess.rows/0`, `plans/0`, `channels/0`, `headline/2`; `MetricsAccessFormat.*`.
- Produces DOM ids tests rely on: `#plan-picker`, `#plan-<key>` (buttons/links), `#plan-summary`, `#category-rail`, `#category-all`, `#category-<slug>`, `#metric-search` (in `#metrics-access-filters` form, `phx-change`), `#dates-relative`, `#dates-exact`, `#metric-rows` (`phx-update="stream"`), `#metric-empty`, row ids from the stream, cells `#<row dom id>-sanbase` / `-api`, header items `#section-<slug>`.

- [ ] **Step 1: Write failing tests** (`use SanbaseWeb.ConnCase, async: false`; fixtures like Task 3; no login):

```elixir
test "renders for an anonymous visitor with Free selected by default"       # has_element?(view, "#plan-free[aria-current=true]")
test "switching plan patches the URL and updates the cells"                  # click #plan-business_pro → assert_patch "/metrics_access?plan=business_pro"; mvrv cell -api text "Last 2 years"
test "dates=exact shows resolved dates"                                      # "Since " <> Date.to_iso8601(Date.add(Date.utc_today(), -730))
test "category filter shows only that category"                             # has_element?/refute has_element? on row ids
test "search matches display and technical names, case-insensitive"
test "regex characters in search do not crash and show the empty state"     # Review Focus 3: q="(*[" → has_element?(view, "#metric-empty")
test "bogus params fall back to defaults"                                    # Review Focus 4: live(conn, "/metrics_access?plan=bogus&category=nope&dates=foo")
test "a cell locked only in one channel does not grey the whole row"         # max-only via set sanapi_min_plan "max", sanbase "free"
test "Business plan cards say which Sanbase plan they include"              # #plan-business_pro has "Includes Sanbase Pro"; #plan-business_max "Includes Sanbase Max"
test "only the first page renders, Show more appends without duplicate headers"
  # with page size overridden small via a module attribute/app env for the test: count rows == size;
  # click #show-more → more rows; every #section-* id appears once
test "search on a variant name shows that variant inline"                    # q="mvrv_usd_30d" → element "#<row id>-matched" contains "mvrv_usd_30d"
```

- [ ] **Step 2: Run — expect FAIL** (no route).

- [ ] **Step 3: Implement**
  - `mount/3`: page title "Santiment | Metrics by plan" only. **Do not assign rows** — every visitor process would hold them.
  - `handle_params/3`: `today = Date.utc_today()` here (not in mount). Parse/validate params into `%{plan, category, q, dates}` (unknown → default). Read `PlanMetricAccess.rows()`, filter (`String.contains?/2` on downcased name + metric names; record matched variant names per row), build items interleaving `%{kind: :header, id: "section-<slug>", label: "Category › Group"}` at group transitions (headers also in "All"). Stream only the first `@page_size` (150) items with `reset: true`; assign `loaded` (count), `last_section` (slug of the last header emitted), per-channel counts (`included` = not `{:locked, _}`), `rail` (categories with counts from the q-filtered rows). Category/search change → `loaded` back to 150; plan/date change → keep `loaded`, re-stream that many.
  - `"load_more"` event (`phx-viewport-bottom` on the list and `#show-more` button, hidden when all loaded): rebuild items from cache, take the next 150, emit a header at the slice start only if its section differs from `last_section`, `stream(:rows, next, at: -1)`.
  - Events: form `phx-change` on search (debounce 200) and the date toggle `push_patch(replace: true)` with defaults omitted; plan and category are `<.link patch>`.
  - Look (spec sketch): sticky top bar with plan picker as segmented cards (label + both headlines; Business Pro "Includes Sanbase Pro", Business Max "Includes Sanbase Max"), summary strip with per-channel counts, left rail (`md:` and up; `<select>` below `md`), table rows: display name, technical name (mono, muted, `+N variants` with `<details>` listing them), two cells. `:free` → "Free · full access" accent; window → history + lag lines; locked → lock icon + `locked/1`, muted; whole row muted only when both channels locked. Transitions on hover/plan switch (`transition-colors`, `duration-150`).
  - Route in `router.ex` next to `/available_metrics`.

- [ ] **Step 4: Run — expect PASS**: `mix test test/sanbase_web/live/metrics_access_live_test.exs`

- [ ] **Step 5: Full check**: `mix precommit` → fix everything it reports; re-run Tasks 1–5 test files.

- [ ] **Step 6: Stop for Ivan.** Suggested message: `Add public metrics-by-plan page`. Tell Ivan how to view it locally: `iex -S mix phx.server` then `http://localhost:4000/metrics_access` (he runs it).
