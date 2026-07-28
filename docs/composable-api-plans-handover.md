# Handover: Composable API Data Packages

**Status:** Scope / design — billing implementation not started
**Date:** 2026-07-27
**Code verified against:** `c7754293a` (master)

**Related product docs (Notion):**
- [Market data plan](https://app.notion.com/p/santiment/Market-data-plan-3912a82d136180d4a99cd1ad45c9122e)
- [Development data package](https://app.notion.com/p/santiment/Development-data-package-37d2a82d136180bda65df9debcd27503)
- [Social data plan](https://app.notion.com/p/santiment/Social-data-plan-37d2a82d136180cf8711e9a0e1f8419c)
- [Onchain core plan](https://app.notion.com/p/santiment/Onchain-core-plan-3842a82d13618064814bf990b6ba1ddb)
- Onchain Labels (final list) — Notion page referenced in the original task

**Related PRs / branches already done:**
- Metric registry categorization (largely applied in production admin; ~1025/1046 categorized)
- Category/group filters on Available Metrics LiveView (`add-category-filters-available-metrics`)
- Laptop viewport / table layout fix (`available-metrics-laptop-viewport-fix`, merged)

**Notation used in this doc:**

| Marker | Meaning |
|--------|---------|
| ✅ | Verified by reading the code at `c7754293a`; `file:line` given |
| ⚠️ | Assumption or open product decision — do **not** build on it without confirming |
| 🔴 | Verified code that breaks or silently misbehaves under a multi-item subscription or an unknown plan name |

---

## 0. TL;DR for whoever picks this up

1. **Design: a `BUNDLE` plan marker + an entirely new entitlement path.** The `plans` row carries a plain marker name (`BUNDLE`) that encodes **nothing**. When the plan name is a bundle, a **new** code path decodes the subscription's items into an entitlement and answers all access and quota questions from it. Existing plans keep their existing code paths, untouched. See §5.
2. **Backward compatibility is a deliverable, not a caveat.** It has its own subtask (§8, task **BC**), its own contract (§7.1), its own test strategy (§7.4), and its own DoD line (§12). The single most valuable thing to build first is the characterization test suite that pins today's behavior.
3. **The entire risk of this design is one thing: finding every `case plan_name` site.** ✅ There are **8 functions with no catch-all clause** that raise `CaseClauseError` on a `BUNDLE` name — including `Plan.plan_name/1`, which runs on **every authenticated request**. Another **9** have catch-alls, so they don't crash; they silently grant the *wrong* access or quota. §7.5 is the complete verified inventory. §7.6 is the mechanism that turns a missed site into a compile error instead of a production 500 — **build it before the feature.**
4. **The product model in the original write-up is missing two dimensions** the code will force you to answer: data windows (historical depth / realtime cutoff) and query/signal access. Metrics alone will under-deliver Onchain Labels and Social. See §6.2.
5. **Two of the original "open questions" are answered by the code.** Package prices must *not* become rows in `plans` (§7.3 #2); hour/minute rate limits must *not* be summed (§6.2). See §9.
6. **Do Stripe last, not first.** The catalog is cheap and reversible; entitlement semantics are not. See §8.

---

## 1. Goal

Sell **recurring API subscriptions** as **composable packages** of metrics (Market, Development, Social Sentiment, Onchain Core, Onchain Labels), optionally with **extra API call add-ons**, under **one Stripe subscription / one invoice**.

Customers should be able to:
- Buy any combination of packages (e.g. Social + Onchain without Development)
- Add / remove packages later
- Add extra API calls
- Cancel

Access and quotas must follow the items on that subscription.

**Existing plans (FREE, BASIC, PRO, …, `CUSTOM_*`) must keep working exactly as today.** This is a hard requirement with its own acceptance criteria — see §7.

---

## 2. Original Notion task (taxonomy + plans)

The original product task asked for five data packages, each with:

1. **Metric taxonomy** — Category → Groups → metrics (from Notion tables), including dual-group membership and moves (e.g. `nft_market_volume` → Onchain Labels; "Move to onchain labels" rows).
2. **`available_metrics`** — Filter by category/group; hide Deprecated / Internal Metrics.
3. **Stripe plan per package** — Market, Development, Social Sentiment, Onchain(Core), Onchain Labels.

### Packages & categories (from Notion)

| Package | Category | Notes |
|---------|----------|--------|
| Market data | Market | Groups: Pricing, Marketcap, Volume, ETF, Indicators, NFT, Deprecated, Funding rates, Open Interest; research Qs on volume / CME / CryptoCompare liquidations |
| Development data | Development (implied) | Groups: Development activity, contributors, Github activity, Github contributors count |
| Social Sentiment | Social Sentiment | Many sentiment groups; also dual membership (e.g. Positive/Negative → Regular Sentiment); exclude Deprecated + Internal from sellable surface |
| Onchain Core | Onchain(Core) | Overview, Fees, Holders, Network Activity (+ nested groups), Network value groups, Staking, Miners, XRPL, NFT; moves to Onchain Labels |
| Onchain Labels | Onchain Labels | Lending, Aggregated lending, Yield, DEXes, NFT, CEX, Whales, Labeled supply, Top holders, Labeled balances, Deprecated |

### Taxonomy status (mostly done)

- Admin UI: `/admin/metric_registry/categorization`
- Dmitry defined categorization on paper; Ivan applied via scripts
- ~**1025 / 1046** metrics categorized (21 left at last check)
- Scripts exist, e.g. `scripts/move_onchain_metrics_to_onchain_labels_category.exs`, `scripts/move_social_metrics_to_social_category.exs`
- Categories/groups are **UI taxonomy** today — they do **not** yet drive billing access

### Available Metrics LiveView (done)

- Filters by **category** and **group** (cascading groups; Uncategorized / Ungrouped)
- Metrics enriched from `metric_category_mappings` (registry templates resolved to public names)
- CSV export includes Category / Group
- Table layout fixed for laptop (horizontal scroll, sticky Name column, no letter-wrapping)

---

## 3. What the Notion task did *not* specify (colleague expansion)

Colleague notes (paraphrased):

> We need subscription plans that can be **bundled** — Social + Onchain without Development, etc.
> Make it work in Stripe as **1 subscription** with **multiple items** → 1 invoice.
> Internals today pick **1 subscription/plan** into API context; with bundles we need **all** purchased packages (or a resolved entitlements struct in `:persistent_term`).
> Each bundle might include **100k API calls** by default; customers can buy **extra** (e.g. +500k).
> Two bundles → prefer **100k + 100k = 200k shared** calls (do **not** split per package).
> Unclear whether to use a `BUNDLE_*` prefix like `CUSTOM_*`.

**API call stacking / extra call add-ons are not in the Notion write-up** — they are product/architecture scope needed for composable selling.

**Decision on the prefix: `BUNDLE`, not `CUSTOM_`** — see §5.2.

---

## 4. Current architecture (verified)

```
Auth → AuthPlug picks ONE subscription + derives ONE plan name into Absinthe context
     → RequestHaltPlug checks ApiCallLimit (minute/hour/month)
     → AccessControl: plan_has_access? + historical/realtime windows
     → Resolver
     → AbsintheBeforeSend increments ApiCallLimit usage
```

| Area | Today | Verified |
|------|--------|----------|
| Products | SANAPI (1), SANBASE (2) — one current subscription per product | ✅ `subscription.ex:713-720` |
| Current sub selection | Newest active/trialing sub for the product wins: `order_by: [desc: id], limit: 1` | ✅ `subscription/query.ex:83-89` |
| Plans | FREE…MAX, BUSINESS_*, CUSTOM; `CUSTOM_*` carries an embedded `Restrictions` struct | ✅ `plan.ex:52-53` |
| Access dispatch | **By plan-name prefix**: `"CUSTOM_" <> _` → `CustomAccessChecker`, else `StandardAccessChecker` | ✅ `access_checker.ex:28-33`, `:50-63` |
| Quota dispatch | **By plan-name prefix**: `"sanapi_custom_" <> _` → `CustomPlan.Access.api_call_limits/2` | ✅ `api_call_limit.ex:513`, `:541` |
| Stripe subscribe | Always a single item | ✅ `stripe_api.ex:176` + callers |
| Stripe upgrade | Rewrites **item[0]'s** plan | 🔴 `stripe_api.ex:210-215` |
| Local DB | `subscriptions.plan_id` **singular** `belongs_to`; sync reads `items.data \|> hd()` | 🔴 `subscription.ex:752-757`, `stripe_event.ex:152`, `stripe_sync.ex:66` |
| Categories | `metric_categories` → `metric_groups` → `metric_category_mappings` — **not** used for access | ✅ `metric/category/*` |
| `subscription_items` table | **Does not exist** | ✅ no hits in `lib/`, `priv/` |

### Key modules

| Concern | Paths |
|---------|--------|
| Product / Plan | `lib/sanbase/billing/product.ex`, `plan.ex` |
| Subscription | `lib/sanbase/billing/subscription/subscription.ex`, `query.ex` |
| Access | `lib/sanbase/billing/plan/access_checker.ex`, `standard_access_checker/*`, `custom_plan/*` |
| Auth context | `lib/sanbase_web/graphql/plugs/auth_plug.ex` |
| Quotas | `lib/sanbase/api_call_limit/*` |
| Stripe | `lib/sanbase/stripe/stripe_api.ex`, `lib/sanbase/billing/stripe_event.ex`, `stripe_sync.ex` |
| GraphQL billing | `billing_queries.ex:127/149/162` (`subscribe`, `update_subscription`, `cancel_subscription`), `billing_resolver.ex` |
| Categories | `lib/sanbase/metric/category/*`, admin LiveViews under `metric_registry/categorization_live/` |
| Available metrics | `lib/sanbase/available_metrics/available_metrics.ex`, `AvailableMetricsLive`, `metric_resolver.ex:62` |

---

## 5. Architecture: `BUNDLE` plan marker + a new entitlement path

### 5.0 The decision

**The plan name is a *marker*, not data.** A `plans` row named `BUNDLE` says only "this subscription's entitlement comes from its items." Everything else is decoded from `subscription_items` at sync time.

```
plans row: BUNDLE (SanAPI)  ──▶  Plan.type/1 == :bundle
                                    │
subscription_items ──▶ decode ──▶ %Entitlement{}  ──▶ access? · quota · windows
  (packages + add-ons)                 │
                                 package definitions
```

**Explicitly rejected:** encoding the entitlement into the plan name (`CUSTOM_PKG_MKT-SOC_700K`). It is a lossy key, it breaks the moment a new dimension is added, and it requires a global cache keyed on a synthetic string.

**Rules of the design:**

| Rule | Consequence |
|------|-------------|
| The plan name carries **no data** | Adding a package or add-on tier never changes a name, invalidates a cache, or touches a pattern match |
| Bundles get an **entirely new code path** | Existing plans' code is not modified, only *branched around* — the strongest possible BC guarantee |
| Prefix is `BUNDLE` | Cannot be confused with bespoke `CUSTOM_*` customers in admin, stats, or support; cannot silently inherit future `CUSTOM_*` behavior changes |
| Entitlement is **resolved at sync time**, not per request | No per-request decode, no cache invalidation, survives restarts (§5.4) |

### 5.1 What can be reused from the `CUSTOM_*` implementation

`CustomPlan.Restrictions` (`custom_plan_restrictions.ex:6-16`) is already the entitlements struct:

```elixir
embedded_schema do
  field(:restricted_access_as_plan, :string)   # what tier this behaves as elsewhere / Sanbase fallback
  field(:api_call_limits, :map)                # %{"month" =>, "hour" =>, "minute" =>} | %{"has_limits" => false}
  field(:historical_data_in_days, :integer)
  field(:realtime_data_cut_off_in_days, :integer)
  field(:metric_access, :map)                  # accessible | accessible_patterns | not_accessible | not_accessible_patterns
  field(:query_access, :map)
  field(:signal_access, :map)
end
```

Everything downstream reads it through **one function**: `CustomPlan.Loader.get_data(plan_name, product_code)` (`custom_plan_loader.ex:16`). `CustomPlan.Access` (`custom_plan_access.ex`) is a thin façade over it exposing exactly the six things the request path needs — `plan_has_access?/3`, `get_available_metrics_for_plan/3`, `api_call_limits/2`, `historical_data_in_days/4`, `realtime_data_cut_off_in_days/4`, `restricted_access_as_plan/2`.

**What to reuse:** the **shape** of `Restrictions` (accessible / accessible_patterns / not_accessible / not_accessible_patterns per metric/query/signal, plus quota and window fields) and the **façade shape** of `CustomPlan.Access` — six functions, one lookup. Model `Bundle.Access` on it so the two paths are recognisably parallel and reviewable side by side.

**What not to reuse:** the `plans`-row storage, `get_plan/2`, and the `:persistent_term` cache keyed by plan name. Bundle entitlements come from items, so they are per-subscription, not per-plan (§5.4).

### 5.2 Why the prefix is `BUNDLE`, not `CUSTOM_`

An earlier draft of this doc argued the prefix *had* to be `CUSTOM_`. That was conditional on the rejected name-encoding design, where the goal was to reuse the existing dispatch without adding branches. Once bundles get their own deliberate code path, `BUNDLE` is the better choice:

- **Greppable.** `Plan.type(name) == :bundle` and `"BUNDLE" <> _` make every bundle-aware site findable. A bundle disguised as `CUSTOM_*` is invisible.
- **Decoupled.** Bespoke `CUSTOM_*` plans are hand-built for individual enterprise customers and their semantics will keep changing. Sharing a prefix means every future change to custom-plan behavior silently changes bundle behavior.
- **No accidental inheritance.** `CUSTOM_*` carries `restricted_access_as_plan` ("behave as PRO elsewhere"), `@custom_plan_stats`, and a `ReadOnly` ClickHouse repo mapping. Bundles should opt into each of those explicitly, not inherit them.
- **Support and reporting.** Admin, MRR stats, and support tooling can tell a bundle from a bespoke enterprise contract at a glance.

**Use the prefix form `"BUNDLE" <> _` in every match** — it matches both the flat `BUNDLE` and a future `BUNDLE_SANBASE`, so the dispatch survives a rename. The row itself is named **`BUNDLE`** — see §5.7 for why, and for the exact rows to create.

🔴 **The cost of this choice is real and must be paid deliberately:** the `CUSTOM_` prefix was already handled at ~17 dispatch sites; `BUNDLE` is handled at none. **8 of those sites have no catch-all and will raise `CaseClauseError`.** The complete inventory is §7.5 and the safety mechanism is §7.6. Do not start the feature before §7.6 exists.

### 5.3 The entitlement value

A plain struct, versioned, with no encoding tricks:

```elixir
%Sanbase.Billing.Bundle.Entitlement{
  packages:            [:market, :social_sentiment],       # audit / display / invoice lines
  metric_access:       %{"accessible" => [...], "accessible_patterns" => [...], ...},
  query_access:        %{...},
  signal_access:       %{...},
  api_call_limits:     %{month: 700_000, hour: 30_000, minute: 300},
  historical_data_in_days: nil,
  realtime_data_cut_off_in_days: 0,
  package_snapshot_version: 7,
  schema_version: 1
}
```

`packages` is kept alongside the resolved sets so support and invoicing can answer "what did they buy?" without reverse-engineering it from a metric list.

### 5.4 Where the entitlement lives: resolve at sync, store on the subscription

The design says "decode the items." The only real question is **when**. Per-request decode is the wrong answer: `effective_plan_name/2` runs on **every authenticated request** (`auth_plug.ex:350-362`) and `@preload_fields` is only `[:user, plan: [:product]]` (`subscription.ex:32`) — items are not preloaded, so per-request decode adds a join plus a resolve to every call.

**Recommended: resolve once at subscribe/webhook-sync time and store the result as JSONB on the subscription row** (`subscriptions.bundle_entitlement`). This gives:

- **No cache.** No boot-time registration, no ETS/`persistent_term` table, no invalidation logic, no staleness window after a Stripe webhook, no missing-key crash path.
- **One write path.** The entitlement changes only when items change, which is exactly when a webhook fires.
- **Free reads.** AuthPlug already loads the subscription; add the column to the existing query.
- **Auditability.** The row records what the customer was entitled to at that point in time, which is what a billing dispute needs.

Two supporting pieces:

- **Package definitions** (package → metric/query/signal rules) *are* static and change on deploy or admin-publish. Those belong in `:persistent_term`, loaded at boot — the existing `CustomPlan.Loader.put_plans_in_persistent_term/0` pattern (`custom_plan_loader.ex:37`) is exactly right here, and it's safe because writes are not customer-triggered.
- **`schema_version` + `package_snapshot_version`** on the stored entitlement, so a stored blob written by older code is detectable. On mismatch, re-resolve rather than trust it.

⚠️ Trade-off to accept explicitly: a stored entitlement is a **denormalised copy**. If a package definition is republished, existing subscriptions keep the old entitlement until re-resolved. That is usually the *desired* billing behavior (customers keep what they bought), but it means "republish a package" needs a deliberate backfill job, not just a deploy. Task **PD** owns that.

### 5.5 What this design does **not** give you

- **`available_metrics` / `AvailableMetricsLive`** — ✅ `available_metrics.ex` contains **no** plan or subscription reference at all. Genuinely new work (task **AM**).
- **`getAvailableMetrics(plan:, product:)`** — ✅ the `plan` arg is `enum :plans_enum` (`metric_types.ex:17-25`) with values `free`/`basic`/`pro`/`max`/`business_pro`/`business_max`/`custom` only. A bundle **cannot be expressed** through this API. Needs either a `bundle` enum value or a caller-context variant.
- **Purchase UI** — nothing in the backend design covers the pricing page / checkout (task **UI**).
- **Stripe multi-item lifecycle** — items, proration, webhooks (tasks **SC**, **LC**, **WH**).
- **Package → metric-set definition** — the actual content of each package (task **PD**).

### 5.6 Confidence

**High** that this design is BC-correct *provided* §7.5 is complete and §7.6 is built — the branch-around approach cannot change existing-plan behavior because it never enters existing-plan code. **High** that the inventory in §7.5 is accurate for the sites listed; **medium** that it is exhaustive, which is precisely why §7.6 (compile-time exhaustiveness + a runtime smoke matrix) matters more than careful reading. **High** that storing the entitlement on the subscription row beats caching it.

### 5.7 The plan rows: `BUNDLE` on SanAPI

**Name: `BUNDLE`. Not `BUNDLE_API`.** The `_API` suffix would duplicate information that is already in `product_id`. ✅ Every existing plan name is a pure tier — `FREE`, `PRO`, `BUSINESS_MAX` — and the same name appears on both products; the attribute encoding that is literally called `@same_name_plans` (`plan.ex:131-141`).

There is also a concrete consequence. ✅ `subscription_to_plan_name/1` (`api_call_limit.ex:359-366`) builds `"sanapi_#{plan_name}"` downcased, so:

| Plan name | `api_calls_limit_plan` value |
|---|---|
| `BUNDLE_API` | `sanapi_bundle_api` — "api" twice |
| `BUNDLE` | `sanapi_bundle` — matches `sanapi_pro`, `sanbase_pro` |

Dispatch matches the prefix form `"BUNDLE" <> _`, so both work and a future `BUNDLE_SANBASE` is already covered. The bare name is simply the one that fits the convention.

**Rows to create** (follow the existing two-rows-per-tier pattern — ✅ `plan_pro` / `plan_pro_yearly` are both named `PRO` and differ only in `interval` and `amount`):

| name | product | interval | amount | is_private | has_custom_restrictions |
|---|---|---|---|---|---|
| `BUNDLE` | SanAPI (1) | `month` | 0 | `false` | **unset** |
| `BUNDLE` | SanAPI (1) | `year` | 0 | `false` | **unset** |

- **`amount: 0`** — the real amounts live per-item in Stripe and the price catalog (§7.3 #2). ✅ Revenue reporting reads Stripe prices (`timeseries.ex:239`), not `plans.amount`, so this is cosmetic. Comment the seed so nobody mistakes it for a figure.
- **`is_private: false`** — unlike `CUSTOM_*` (which is private because it is hand-built per enterprise customer), bundles are self-serve.
- **`has_custom_restrictions` must stay unset** — see §7.5 C2.
- **Choose the ids deliberately**, in the same low range as the other production plans. ✅ Seeded plans use hardcoded ids and `plans_id_seq` is reserved for custom plans (`custom_plan_test.exs` restarts it at 1001).
- The two interval rows are also where **one interval per subscription** is tracked: the subscription points at whichever row matches its items' interval.

**Monthly and yearly cannot be mixed in one subscription** (confirmed — Stripe requires all recurring prices in a subscription to share an interval, and it is also the product decision). Three consequences that are easy to miss:

1. **Every sku needs both variants.** Each package price, each full-history add-on and each extra-calls add-on must exist in monthly *and* yearly form, or a monthly subscriber cannot buy an add-on that only exists yearly. So `interval` is a first-class column on the price catalog, and the purchase UI must filter available skus by the subscription's existing interval. This roughly doubles the catalog — 5 packages + 5 history add-ons + N call tiers, ×2.
2. **Switching monthly ↔ yearly is not an add/remove-item operation.** It swaps *every* item to its counterpart price and repoints `subscriptions.plan_id` at the other `BUNDLE` row. Stripe can do it in one update with proration, but the local sync has to move `plan_id` too — otherwise the subscription claims an interval its items no longer have. Task **SL** owns it as a distinct mutation.
3. **Validate at subscribe and at add-item.** Reject a mixed-interval cart before calling Stripe rather than surfacing a Stripe error, and reject adding a yearly package to a monthly subscription. The webhook sync should also flag a mixed-interval subscription if one ever appears, rather than silently resolving an entitlement from it.

**Why SanAPI, even though Institutional includes Sanbase.** ⚠️ The Institutional tier is "Full Sanbase + Full SanAPI + MCP", so that entitlement spans both products. It still belongs on SanAPI, because the fallback already exists: ✅ `get_user_subscription_for_sanbase/1` (`auth_plug.ex:374-380`) tries the Sanbase subscription and then falls back to the SanAPI one, commented *"so paying SanAPI users keep their Sanbase benefits."* So a SanAPI-hosted bundle whose entitlement names the Sanbase tier it behaves as (Institutional → `PRO_PLUS`, single pillars → `FREE`) reuses a working path instead of inventing cross-product subscriptions — and two subscriptions would break the one-invoice promise anyway.

**Vocabulary.** The pricing page says "package", the code says "bundle". That is not a mismatch, and it is worth stating once so the two words do not drift:

- **package** = one pillar = one Stripe line item = `type: :package`
- **bundle** = the composed subscription = the `plans` row

A bundle is made of packages.

---

## 6. Target product model

### 6.1 Sellable line items (recurring)

| Item | Type | Effect |
|------|------|--------|
| Market data | package | Unlock Market metrics (minus Deprecated) |
| Development data | package | Unlock Development metrics |
| Social Sentiment | package | Unlock Social Sentiment (minus Deprecated/Internal) |
| Onchain (Core) | package | Unlock Onchain Core |
| Onchain Labels | package | Unlock Onchain Labels |
| Extra API calls | quota add-on | e.g. +500k / month |

### 6.2 An entitlement has **five** dimensions, not two

The original write-up specified only metrics and monthly calls. `Restrictions` requires more, and `validate_required` (`custom_plan_restrictions.ex:28`) makes some of it mandatory:

| Dimension | Combination rule | Status |
|-----------|------------------|--------|
| **Metrics** | union of packages | agreed |
| **Queries** (`query_access`) | union — **required field**, cannot be omitted | ⚠️ **unspecified** — see below |
| **Signals** (`signal_access`) | union — **required field** | ⚠️ **unspecified** |
| **Data windows** (`historical_data_in_days`, `realtime_data_cut_off_in_days`) | ⚠️ **undecided** — recommend max (most generous) across purchased packages, or a single value on the base plan | ⚠️ **unspecified — biggest hole** |
| **API calls** | month: **sum** of package bases + add-ons. hour/minute: **do not sum** — see below | partially specified |

**Queries and signals are not optional.** There are ~13 `access: :restricted` GraphQL queries, and they map directly onto the packages being sold — `historical_balance_queries.ex:114` (`min_plan: [sanapi: "PRO"]`), `blockchain_metric_queries.ex`, `social_data_queries.ex`. Top-holders and historical-balance functionality is core Onchain Labels surface and it lives in **queries**, not the metric registry. A package defined only as a metric set will under-deliver Onchain Labels and Social. ✅ verified.

**Data windows are the biggest hole.** `nil` means *no restriction* (`custom_access_checker.ex:36-39` docstring), so leaving these unset ships **full history and full realtime** with a 100k-call package. Every existing tier differentiates on this axis. Must be decided in task **A**.

**Do not sum hour/minute limits.** `validate_api_calls` requires `month > hour > minute > 0` (`custom_plan_restrictions.ex:56-70`). Summing per-package rate limits makes burst capacity scale with *entitlement breadth*, but rate limits exist to protect infrastructure, not to price data. Recommend: **sum month; take max (or a fixed base-plan value) for hour and minute.** ✅ verified.

**Sanity-check the quota pricing.** `sanapi_pro` is already **600k/month** (`api_call_limit/restrictions.ex:10`). At 100k per package, all five packages = 500k — *less* than today's PRO, presumably at a higher total price. Either the 100k base is too low or the add-on is effectively mandatory. ⚠️ Resolve in task **A** before any Stripe price exists.

**Minor:** response-size limits only apply when status is `trialing` or plan is `sanapi_free` (`api_call_limit.ex:397-401`), and `CustomPlan.Access.response_size_limits/2` is a hardcoded TODO (`custom_plan_access.ex:12-17`). So a *trialing* bundle sub would get a 200,000 MB/month allowance — effectively unlimited. Harmless, but note it if bundles get trials (task **TR**).

### 6.3 Rules (recommended)

1. Metric / query / signal access = **union** of purchased packages
2. Monthly API call limit = **sum** of per-package bases + add-ons
3. One **shared** call bucket (never split Social vs Onchain rate limits)
4. Hour/minute limits from a **single base value**, not summed
5. Data windows = **max** across purchased packages ⚠️
6. One Stripe subscription, many items, one invoice (Stripe native)
7. Prefer composition of prices over combinatorial fixed combo SKUs
8. Plan naming: `plans` rows named `BUNDLE` on SanAPI (one per interval) as markers; the entitlement comes from the items (§5.0, §5.7)

---

## 7. Backward compatibility (first-class requirement)

### 7.1 The BC contract

> For any user who does **not** hold a bundle subscription, every observable behavior is byte-identical to `c7754293a`: metric access, query access, signal access, `restrictedFrom` / `restrictedTo` windows, API call limits, response-size limits, alert limits, credits and query-execution limits, Sanbase fallback tier, report/webinar/sheet gating, admin subscription views, and revenue stats.

"Observable" includes GraphQL error messages and the `plan_name` string exposed via `billing_types.ex:52` / `billing_resolver.ex:395`. ✅ That resolver reads `Plan.plan_name(sub.plan)` from the **DB** plan, so bundles will surface as `BUNDLE` — decide whether the frontend needs a friendlier display name, and note that `Plan.plan_name/1` must gain a `BUNDLE` clause first or it raises (§7.5 A1).

### 7.2 Why "branch around" is the BC-safest structure

Existing-plan code is never **modified**, only **branched around**. A bundle request diverges at the top of each dispatch function and never re-enters the standard or custom path. This yields the review rule for the whole epic:

> **Every diff in this epic is either (a) a new `:bundle` clause added at the top of an existing dispatch function, (b) new code in a new module, or (c) a new column / table. Any diff that changes the *body* of an existing plan's branch is out of scope and should be rejected in review.**

That is a mechanically checkable rule — it does not depend on reasoning about behavior.

**The corresponding weakness, stated plainly:** BC now depends entirely on **finding every dispatch site**. Missing one does not degrade gracefully — 8 of them raise `CaseClauseError`, and one of those runs on every authenticated request. §7.5 is the inventory; §7.6 is the mechanism that makes completeness verifiable rather than hoped-for.

*(An earlier draft argued for reusing the `CUSTOM_` prefix so that no new branches were needed. That is rejected — see §5.2. The branch cost is accepted deliberately in exchange for a bundle path that is greppable and decoupled from bespoke enterprise plans.)*

### 7.3 Verified BC hazards (all are 🔴 multi-item bugs in *existing* code)

These do not break today. They break the moment a subscription has more than one Stripe item, so each needs an explicit guard **and** a test.

| # | Site | What happens | Required guard |
|---|------|--------------|----------------|
| 1 | `stripe_api.ex:210-215` `get_upgrade_downgrade_subscription_params/2` | Fetches the **first** item id and calls `update_subscription` with `items: [%{id: item_id, plan: …}]`. On a bundle sub this **rewrites item[0]'s price and silently corrupts the purchased set and the invoice.** This is a *write*, making it the most dangerous site. | Reject bundle subs in `upgrade_downgrade/2`; route them through the new item mutations only |
| 2 | `subscription.ex:752-757` `fetch_plan_id/2` | Takes item[0]'s plan, looks up `Plan.by_stripe_id/1`, and **overwrites `subscriptions.plan_id`** on every sync. Falls back to the existing `plan_id` only when the price is unknown. | **Do not create `plans` rows for package prices.** Package/add-on prices belong in a separate catalog table. This resolves the "local plan rows *or* catalog table" ambiguity in the original task B — it must be a catalog table. |
| 3 | `stripe_event.ex:150-155` `handle_subscription_created/3` | Resolves the plan from item[0] via `Plan.by_stripe_id/1` and errors `{:plan?, _}` if not found. Stripe does not guarantee item order, so a bundle sub either fails to sync or binds to the wrong plan. | Find the **base** item explicitly by matching known price ids; branch bundle vs legacy |
| 4 | `stripe_sync.ex:66` | `subscription.items.data \|> List.first()` | Branch by subscription type |
| 5 | `timeseries.ex:239` | `(subscription.items.data \|> hd()).price` — revenue/stats attribution | Sum across items for bundle subs, else misreported MRR |
| 6 | `subscription.ex:594-599` `has_active_subscriptions/2` | Guards duplicates **per `plan.id` only**, so PRO + composable on SANAPI is structurally allowed. Combined with `order_by: [desc: id], limit: 1` (`query.ex:83-89`), the **newest subscription silently wins while the other is paid for and ignored.** | Enforce one-active-subscription-per-product at subscribe time, with a test. Not merely a "policy question" — it is a live billing bug waiting for a second sub. |
| 7 | `custom_plan_loader.ex:20` | Missing cache entry raises `MatchError`; the `{:error, _}` branch in `queries/authorization.ex:195` is dead code | Lazy resolve + genuine error tuple (§5.4b) |

### 7.4 BC test strategy — build this **first**

`test/sanbase/billing/metric_access_level_test.exs` (1831 lines) and `query_access_level_test.exs` (242 lines) already pin metric/query *access-level classification* with hardcoded expected lists. That is the right pattern; extend it to the full entitlement matrix **before** writing any production code:

1. **Characterization fixture** — for every plan name × product × a representative sample of metrics/queries/signals, snapshot: `plan_has_access?`, `historical_data_in_days`, `realtime_data_cut_off_in_days`, `api_call_limits`, `response_size_limits`, `restricted_access_as_plan`, `alerts_limit`, `credits_limit`, `query_executions_limit`. Commit it as a golden file generated from `c7754293a`.
2. **Assert unchanged** in CI on every subsequent commit of this epic. Any diff must be an explicit, reviewed fixture update.
3. **Include today's bespoke `CUSTOM_*` plans** from a seeded fixture — they share the code path composable will use and are the most likely collateral damage.
4. **Multi-item guard tests** — one test per row in §7.3 asserting the guard fires (mocked Stripe).
5. **Legacy single-item webhook tests** must keep passing untouched; do not edit them to accommodate new branching.

This suite is the acceptance criterion for the BC contract in §7.1.

### 7.5 Dispatch-site inventory — every site that must learn about `:bundle`

✅ All rows read at `c7754293a`. This is the **critical deliverable of the epic**. Group A crashes; group B silently misbehaves; group C needs a product decision.

#### Group A — no catch-all clause → `CaseClauseError` → 500

| # | Site | Reached via | Blast radius |
|---|------|-------------|--------------|
| **A1** | 🔴🔴 `plan.ex:143-149` `Plan.plan_name/1` | `Subscription.plan_name/1` ← **AuthPlug, every authenticated request** | **Total outage for the bundle user.** A `plans` row named `BUNDLE` crashes before any other code runs. Fix: add a `"BUNDLE" <> _ = name -> name` clause (prefer this over adding to `@same_name_plans` at `plan.ex:131-141`, so the prefix form works) |
| **A2** | `sanbase_access_checker.ex:62-73` `plan_stats/1` | `alerts_limit/1` ← `user_trigger_resolver.ex:63`; `can_access_paywalled_insights?/1` | Alert creation + insight access 500 |
| **A3** | `api_access_checker.ex:68-79` `historical_data_in_days_api/1` | `AccessChecker.historical_data_in_days/4` | Every restricted metric/query 500s |
| **A4** | `api_access_checker.ex:81-88` `historical_data_in_days_sanbase/1` | same, SANBASE product | Sanbase requests 500. Note: today handles only BASIC/PRO/PRO_PLUS/MAX — not even FREE or CUSTOM |
| **A5** | `api_access_checker.ex:98-109` `realtime_data_cut_off_in_days_api/1` | `AccessChecker.realtime_data_cut_off_in_days/4` | Every restricted metric/query 500s |
| **A6** | `api_access_checker.ex:111-118` `realtime_data_cut_off_in_days_sanbase/1` | same, SANBASE product | Sanbase requests 500 |
| **A7** | `queries/authorization.ex:123-155` `query_executions_limit/2` | `user_resolver.ex:245` | `currentUser` query 500s |
| **A8** | `queries/authorization.ex:157-189` `credits_limit/2` | `user_resolver.ex:242` | `currentUser` query 500s |

#### Group B — has a catch-all → no crash, wrong answer

| # | Site | Catch-all does | Why that's wrong for a bundle |
|---|------|----------------|-------------------------------|
| **B1** | `access_checker.ex:27-33` `plan_has_access?/3` | → `StandardAccessChecker` | Bundle evaluated on the **ordinal ladder**, which cannot express packages. Bundle user gets ~FREE access while paying. **Silent under-delivery — the worst failure mode in the list** |
| **B2** | `access_checker.ex:49-63` `get_available_metrics_for_plan/3` | → `StandardAccessChecker` | Wrong metric list returned from `getAvailableMetrics` |
| **B3** | `access_checker.ex:91-…` `historical_data_in_days/4` | → `StandardAccessChecker` → **A3/A4** | Crashes one frame later |
| **B4** | `access_checker.ex:127-…` `realtime_data_cut_off_in_days/4` | → `StandardAccessChecker` → **A5/A6** | Crashes one frame later |
| **B5** | 🔴 `api_call_limit.ex:541-556` `plan_to_api_call_limits/1` | → `@api_call_limits_per_month["sanapi_bundle"]` = **`nil`** | `get_api_calls_maps/1` (`:478-496`) then computes `api_calls_limits.month - api_calls_made.month` → **`ArithmeticError` on nil**. Crashes, just later |
| **B6** | `api_call_limit.ex:560-577` `plan_to_response_size_limits/1` | → `nil` month limit | Same nil arithmetic; only reachable while `trialing` or `sanapi_free` (`:397-401`), so lower priority |
| **B7** | `api_call_limit.ex:510-527` `plan_has_limits?/1` | `_ -> true` | Correct by luck. Still add an explicit clause so intent is recorded |
| **B8** | `queries/authorization.ex:~95-120` `user_plan_to_dynamic_repo/2` | `_ -> ClickhouseRepo.FreeUser` | Bundle queries run on the **free-tier ClickHouse pool** — wrong resource limits, silent |
| **B9** | `api_call_limit.ex:359-366` `subscription_to_plan_name/1` | builds `"sanapi_bundle"` | This is the string that lands in `api_call_limits.api_calls_limit_plan` and drives B5–B7. Decide its form deliberately |

#### Group C — no crash, needs a product decision

| # | Site | Behavior today | Decision needed |
|---|------|----------------|-----------------|
| **C1** | `metric_types.ex:17-25` `enum :plans_enum` | no `bundle` value | Add `bundle`, or add a caller-context variant of `getAvailableMetrics` (task **AM**) |
| **C2** | `auth_plug.ex:350-362` `effective_plan_name/2` | SANBASE branch keys on `has_custom_restrictions: true` | What does a bundle map to for Sanbase? Do **not** set `has_custom_restrictions: true` on the `BUNDLE` rows — it would route into `fetch_base_plan_for_custom/1` → `Loader.get_plan/2` → 🔴 `FunctionClauseError` |
| **C3** | `webinar_resolver.ex:9`, `sheets_template_resolver.ex:8`, `report_resolver.ex:17` | plan-name match finds nothing | Do bundle buyers get reports / webinars / sheet templates? |
| **C4** | `plan.ex:16` `@plans_order` | `Keyword.get` → `nil`; term ordering sorts bundles last | Cosmetic; add an explicit order value |
| **C5** | `generic_admin/subscription.ex`, `subscription/stats.ex`, `timeseries.ex:239` | first-item / plan-name assumptions | Admin display + MRR attribution (see §7.3 #5) |

**Not affected:** `lib/sanbase/billing/plan/restrictions.ex` (252 LOC, the `restrictedFrom`/`restrictedTo` builder) delegates entirely through `AccessChecker`, so fixing B1–B4 covers it. ✅ verified — no plan-name dispatch of its own.

### 7.6 Making a missed site impossible (build this before the feature)

§7.5 is a list a human compiled by reading code. That is not a safe foundation on its own. Two cheap mechanisms convert it into something CI enforces:

**(1) One dispatch seam — `Plan.type/1`.**

```elixir
# lib/sanbase/billing/plan.ex
@type plan_type :: :standard | :custom | :bundle

@spec type(String.t()) :: plan_type()
def type("BUNDLE" <> _), do: :bundle
def type("CUSTOM_" <> _), do: :custom
def type(_), do: :standard
```

Then every site in §7.5 becomes `case Plan.type(plan_name) do :bundle -> …; :custom -> …; :standard -> … end`. Benefits:
- `rg "Plan.type"` enumerates every plan-type-aware site — the inventory stops being a doc and becomes a grep.
- Dispatch is on an **atom from a closed type**, so Dialyzer and `--warnings-as-errors` can flag a missing clause at **compile time** instead of at 3am.
- New plan types later (`:trial`, `:partner`) inherit the same enforcement.

**(2) A plan × entry-point smoke matrix.** One test, high value:

```
for plan_name <- existing_plan_names() ++ ["BUNDLE"],
    product   <- ["SANAPI", "SANBASE"] do
  # assert each returns a value and never raises
end
```

Entry points to cover: `Plan.plan_name/1`, `AccessChecker.plan_has_access?/3`, `historical_data_in_days/4`, `realtime_data_cut_off_in_days/4`, `get_available_metrics_for_plan/3`, `Restrictions.get_all/2`, `ApiCallLimit.plan_to_api_call_limits/1` (+ the full `get_quota/2` path so B5's nil arithmetic is exercised), `SanbaseAccessChecker.alerts_limit/1`, `Authorization.credits_limit/2`, `query_executions_limit/2`, `user_plan_to_dynamic_repo/2`.

This turns "did we find every site?" from a code-review judgement into a CI result — and it would fail today for all eight Group A rows, which makes it a good first commit.

**(3) Prefer a loud failure over a silent one.** Where a catch-all must stay, make it raise a descriptive error rather than fall through to FREE. B1 and B8 already fail silently today; a paying bundle customer receiving FREE-tier access is worse than a 500 caught in staging.

---

## 8. Task split (revised)

Ship as vertical slices. Changes from the original split: BC is promoted to a first-class task and sequenced first; package definition is split out of the decision doc into its own task; Stripe catalog is moved **after** the entitlements core; three missing tasks are added (**OB**, **UI**, plus **AM** made explicit).

### BC. Backward-compatibility safety net
**What:** The characterization suite and golden fixtures of §7.4 (steps 1–3), captured from `c7754293a` before any production change.
**Deliverable:** golden fixture + CI-asserted test module.
**Depends on:** nothing. **Do this first** — it is cheap, it never needs revisiting, and every later task is reviewed against it.

### DP. Dispatch seam + exhaustiveness enforcement
**What:** §7.6 — introduce `Plan.type/1`, refactor the ~20 sites in §7.5 to dispatch on it (mechanical, behavior-preserving, provable against the **BC** fixture), and add the plan × entry-point smoke matrix. No bundle behavior yet; `:bundle` clauses raise `"not implemented"`.
**Deliverable:** `Plan.type/1` + refactor + smoke-matrix test that fails for `BUNDLE` on all Group A rows.
**Depends on:** BC. **Do this second, before any feature work.** It is the difference between "we think we found every site" and "CI proves we did". It also lands as a pure refactor with the fixture green, which makes it a trivial review.

### A. Product decisions
**What:** Lock SKUs, base quota per package, add-on tiers, proration policy, SANAPI-only vs Sanbase scope, PRO-vs-composable precedence, **data windows per package**, **hour/minute limit rule**, **queries + signals per package**.
**Deliverable:** decision doc, then an Elixir config module.
**Depends on:** nothing. The four bolded items are the ones that cause rework if guessed — see §6.2.

### PD. Package definition & snapshot
**What:** The source of truth for what each package contains (metrics + queries + signals). Split out of A because it is a correctness and contractual concern, not a config detail:
- `metric_category_mappings` is edited continuously by admins in the categorization LiveView. If access reads **live** category membership, an admin re-categorizing one metric silently **grants or revokes** access a customer paid for.
- ✅ The schema has singular `category_id` / `group_id` per row (`metric_category_mapping.ex:42-43`) but a metric may have **multiple** rows, and the Notion task explicitly wants dual membership. A metric in both Onchain Core and Onchain Labels is therefore sellable via either. Fine for a union — but needs a **leak check** that a Market-only buyer cannot pick up Onchain metrics through a second mapping row.

**Recommendation:** define packages as category/group **rules**, materialize to a **versioned snapshot** with a diff preview in admin before publish, and pin each subscription to a snapshot version.
**Deliverable:** package definition module + snapshot table + admin diff view + leak-check test.
**Depends on:** A. ⚠️ Snapshot-vs-live is a real trade-off; live is defensible if you accept that admin category edits *are* billing changes and gate the LiveView accordingly.

### LC. Local multi-item subscription model
**What:** Create the `BUNDLE` plan rows (markers only, one per interval — **not** `has_custom_restrictions: true`; see §5.7 and §7.5 C2). Keep `subscriptions.plan_id` pointing at it. Add `subscription_items` (`stripe_item_id`, `sku`/`price_id`, `quantity`, `type: :package | :api_calls`), a **price catalog table** (not `plans` rows — see §7.3 #2), and `subscriptions.bundle_entitlement` JSONB (§5.4).
**Deliverable:** migration + schemas + sync helpers.
**Depends on:** A. **Not** on the Stripe catalog — seed from fixtures/admin so everything downstream can be built and tested before a Stripe object exists.
**BC:** legacy subs have no `subscription_items` rows and `bundle_entitlement IS NULL`.

### EN. Entitlement resolver (core)
**What:** `items + package_defs -> %Bundle.Entitlement{}` (§5.3). Union metrics/queries/signals, sum monthly calls, apply the window and rate-limit rules from A. Pure function — no DB, no cache, fully unit-testable. Plus the writer that persists it to `subscriptions.bundle_entitlement` and the `schema_version` / `package_snapshot_version` handling.
**Deliverable:** struct + resolver + persistence + unit tests with fixtures.
**Depends on:** A, PD, LC.

### BA. Bundle access path
**What:** The new path itself. `Bundle.Access` — six functions mirroring `CustomPlan.Access` (`plan_has_access?/3`, `get_available_metrics_for_plan/3`, `api_call_limits/2`, `historical_data_in_days/4`, `realtime_data_cut_off_in_days/4`, plus whatever C2 decides for Sanbase) reading the stored entitlement. Then fill in the `:bundle` clause at **every** site from §7.5 groups A and B, replacing the `"not implemented"` raises from **DP**.
**Deliverable:** `Bundle.Access` + ~20 one-line dispatch clauses + tests per site.
**Depends on:** EN, DP. **Highest-risk task in the epic.** Acceptance: the §7.6 smoke matrix is green for `BUNDLE` and the **BC** fixture is unchanged.

### SC. Stripe catalog
**What:** Stripe Product(s) + Prices: base bundle subscription, one price per package, full-history add-on prices, API-call add-on prices — **each in both monthly and yearly form** (§5.7). Sync into the local price catalog with `interval` as a first-class column. Invoice total = sum of items. Set nicknames so customers see "Social Sentiment", not raw price ids.
**Deliverable:** Stripe objects + catalog rows.
**Depends on:** A. Deliberately sequenced **after** EN/DN: the catalog is cheap and reversible, entitlement semantics are not.

### SL. Subscribe / add / remove / cancel
**What:** New mutations for bundles only (`subscribeBundle`, add/remove item, **switch interval**, cancel) using Stripe Subscription Items + proration. Leave `subscribe` / `update_subscription` / `cancel_subscription` (`billing_queries.ex:127/149/162`) untouched, and add the guard from §7.3 #1 so a bundle sub can never reach `upgrade_downgrade/2`. Enforce §7.3 #6 one-active-sub-per-product, and reject mixed-interval carts and mixed-interval add-item before calling Stripe (§5.7).
**Deliverable:** GraphQL + Stripe API + mocked tests.
**Depends on:** SC, LC, BA.

### WH. Webhook / sync for multi-item
**What:** Branch `customer.subscription.created|updated|deleted`: bundle → sync all items, **re-resolve and rewrite `bundle_entitlement`**, reset the `ApiCallLimit` record; else → current first-item behavior unchanged. Handle §7.3 #2–#5. Idempotency: item changes fire many `subscription.updated`, and re-resolving must be a pure recompute so repeats are harmless.
**Deliverable:** updates in the Stripe event → subscription sync path + tests both ways.
**Depends on:** LC, EN. **Critical for BC.**

### AM. `available_metrics` by entitlement
**What:** ✅ `available_metrics.ex` has **no** plan/subscription awareness today, so this is new work. ✅ `getAvailableMetrics`'s `plan` arg is `enum :plans_enum` (`metric_types.ex:17-25`) with no `bundle` value, so a bundle cannot be expressed through it — add the enum value or a caller-context variant (§7.5 C1). Align the LiveView/docs with the category/group filters already shipped.
**Depends on:** EN, BA.

### OB. Admin / support visibility
**What:** An admin view showing a customer's **resolved** entitlements — packages, effective metric/query/signal lists, quota, windows, derived plan name, snapshot version. Without it, every support ticket becomes an engineering ticket, and the "derived plan name that isn't in `plans`" concept is invisible to everyone but its author.
**Depends on:** EN. Small, high value — do not defer it to "later".

### UI. Self-serve purchase surface
**What:** Pricing page / checkout for arbitrary package combinations + add-ons. Nothing in the original A–J covered this, yet §1 requires it and §12 cannot be met without it.
**Depends on:** SC, SL. ⚠️ **Confirm ownership** — if this is a frontend-team deliverable, say so explicitly in the epic rather than leaving it unassigned.

### TR. Trial & dunning semantics
**What:** There is a 14-day trial (`subscription.ex:33`) and `past_due` / `unpaid` statuses. Decide: do bundle subs get trials? Trial × 5 packages? Behavior on dunning — full revoke or degrade to a base package? Also the response-size note in §6.2.
**Depends on:** A.

### TE. Tests (continuous)
- Unit: entitlement union / sum / window math
- Unit: access allow/deny per package; leak check for dual-category metrics (PD)
- Unit: quota math incl. add-ons and the no-summing rule for hour/minute
- Integration: subscribe → add item → webhook → access + quota
- Regression: the **BC** golden fixture, asserted on every commit
- Multi-item guard tests: one per row of §7.3

### Suggested order

```text
BC (characterization fixture — cheap, never revisited)
  → DP (Plan.type/1 seam + smoke matrix)      ← pure refactor, fixture green, trivial review
      → A (decisions: SKUs, windows, queries/signals, rate-limit rule)
          → PD (package definition + snapshot)
          → LC (BUNDLE rows + subscription_items + price catalog + entitlement column)
              → EN (entitlement resolver + persistence)   ← unit-testable, zero Stripe
                  → BA (bundle access path + ~20 dispatch clauses)  ← access & quotas work end-to-end
                      → OB (admin visibility)     ← cheap, unblocks support and reviewers
                      → SC (Stripe catalog)
                          → SL (subscribe/add/remove/cancel)
                              → WH (webhooks/sync)
                                  → UI (purchase surface)
                      → AM (available_metrics)    ← parallel after BA
  TR, TE continuous
```

**First vertical slice that delivers value:** `BC → DP → A → PD → LC → EN → BA`. At the end of it, a bundle subscription seeded by hand grants exactly the right access and quota, the §7.6 smoke matrix is green, the BC fixture is unchanged — and not one Stripe object exists yet.

**Then:** `SC → SL → WH` for the real purchase lifecycle, `UI` for self-serve, `AM`/`OB` for surfacing.

**Why DP comes before A:** it is the only task whose cost *rises* the longer you wait. Done first, it is a behavior-preserving refactor reviewed against a green fixture. Done later, it is entangled with new bundle logic and no longer independently verifiable.

---

## 9. Open product decisions

Now **decided**:

| Decision | Answer | Evidence |
|----------|--------|----------|
| Plan name / prefix? | **`BUNDLE`** on SanAPI, matched as `"BUNDLE" <> _`. The name is a marker and encodes nothing; no `_API` suffix, because the product is already a column. Requires `:bundle` clauses at 12 sites (§7.5). | §5.2, §5.7 |
| Entitlement source | **Decoded from `subscription_items`**, resolved at sync time, stored as JSONB on the subscription row. No global cache, no name encoding. | §5.4 |
| Package prices as `plans` rows or a catalog table? | **Catalog table.** `fetch_plan_id/2` would hijack `subscriptions.plan_id` from item[0]. | §7.3 #2 |
| Coexistence: block PRO + bundle, or define precedence? | **Block.** Today the newest sub silently wins and the other is paid-for-and-ignored — that is a bug, not a precedence rule. | §7.3 #6 |
| `has_custom_restrictions` on the `BUNDLE` rows? | **No.** It would route Sanbase requests into `fetch_base_plan_for_custom/1` → `Loader.get_plan/2` → 🔴 `FunctionClauseError`. | §7.5 C2 |
| Mixed monthly/yearly in one subscription? | **Not possible.** Stripe requires one interval per subscription, and it is also the product decision. Every sku needs both variants; switching interval is its own mutation. | §5.7 |

Still genuinely open (all ⚠️, all belong in task **A** or **PD**):

| Decision | Options / recommendation |
|----------|---------------------------|
| **Data windows per package** | **Highest priority.** `nil` = unlimited history + realtime. Recommend: explicit value, max across purchased packages |
| **Queries & signals per package** | Required by `Restrictions`; must be enumerated per package (Onchain Labels and Social depend on it) |
| Base quota per package | e.g. 100k each — but check against `sanapi_pro` = 600k (§6.2) |
| Extra call SKUs | e.g. +100k, +500k; prices |
| 2 packages → calls | **200k shared** (recommended) vs 100k total vs split pools |
| Hour/minute limits | **Do not sum** (§6.2). Recommend max or a base-plan constant |
| Mid-cycle remove package | Limit drop immediate vs next period; used calls carry over. Recommend: raise immediately, drop at period end |
| Proration | Stripe default immediate invoice vs period end |
| Sanbase | Packages SANAPI-only? What `restricted_access_as_plan` value do they map to for Sanbase fallback? |
| Package ↔ metrics source of truth | Versioned snapshot (recommended) vs live category membership (§8 **PD**) |
| Combination cardinality | Confirm sold combinations stay in the tens (§5.3) |
| Admin tooling | Edit package contents without deploy? (implies snapshot + publish flow) |
| Trials & dunning | §8 **TR** |

---

## 10. Gaps / risks

**Verified multi-item hazards** — all seven are enumerated with guards in §7.3. The two most dangerous are `get_upgrade_downgrade_subscription_params/2` (a *write* that corrupts the item set) and `fetch_plan_id/2` (silently rewrites `plan_id`).

**The dominant risk is dispatch-site completeness** — §7.5 and §7.6. Eight sites raise `CaseClauseError`, one of them (`Plan.plan_name/1`) on every authenticated request, and two more fail silently by granting free-tier access or the free-tier ClickHouse pool to a paying customer. This risk is fully mitigable, but only by building §7.6 first.

**Other risks:**
- **A denormalised entitlement can go stale.** Republishing a package definition does not update existing `bundle_entitlement` blobs. Usually desirable (customers keep what they bought) but it needs a deliberate backfill job — task **PD** owns it. `schema_version` makes staleness detectable.
- **Do not cache bundle entitlements in `:persistent_term`** — a global GC scan per customer-triggered write. Storing on the subscription row (§5.4) avoids the question entirely; package *definitions* are static and belong there.
- **Idempotent webhooks** — item changes fire many `subscription.updated`; re-resolving must be a pure recompute so repeats are harmless.
- **Payment method** — subscribe still needs the SetupIntent / existing payment flow; unchanged by this design but still required for **SL**.
- **Invoice line nicknames** — customers must see "Social Sentiment", not `price_1A2b3C`.
- **Revenue reporting** — `timeseries.ex:239` attributes revenue to item[0]'s price; MRR will be understated for bundle subs until fixed.
- **Taxonomy cleanup** — remaining ~21 uncategorized metrics + Onchain → Labels moves. Now a *billing* blocker if packages read categories: an uncategorized metric is unsellable.
- **Research items** from the Market Notion page (volume vs `volume_usd`, CME, CryptoCompare liquidations, "total volume") — separate from the billing MVP.
- **No per-metric à la carte** and **no per-package call pools** in v1.

---

## 11. Explicit non-goals (v1)

- Rewriting existing plan access or Stripe single-plan checkout
- Encoding the entitlement into the plan name (explicitly rejected — §5.0)
- Unifying the standard ordinal ladder and the allow-list model into one entitlement system (a real improvement, but a separate epic — see §14)
- Fixed combo SKUs for every package combination
- Splitting API call quotas per package
- Blocking on full Notion research answers (CME, liquidations, etc.) before shipping billing

---

## 12. Definition of done

1. User can start a composable API subscription with N packages (+ optional call add-on)
2. One Stripe subscription / one invoice; price updates with items
3. Add / remove / cancel works
4. Metric **and query and signal** access = union of packages; monthly calls = sum; one shared bucket; data windows per the rule from task **A**
5. **The BC golden fixture from §7.4 is green, and every hazard in §7.3 has a guard plus a test.** Existing FREE / BASIC / PRO / `CUSTOM_*` users observe zero change.
6. **The §7.6 smoke matrix passes for `BUNDLE` across every entry point and both products**, and every site in §7.5 groups A and B has an explicit `:bundle` clause — none relying on a catch-all
7. Support can answer "what does this customer have access to?" from the admin UI without engineering help
8. Tests cover entitlements, access, quota math, the multi-item guards, and the happy-path lifecycle

---

## 13. Suggested next concrete step

Three things, in this order. The first two are pure infrastructure and can start immediately — they need no product decisions at all.

1. **Task BC** — the characterization fixture (~a day). Pure upside: required by the DoD, never needs rewriting, and it makes every later review a diff instead of an argument.
2. **Task DP** — `Plan.type/1` + the §7.6 smoke matrix (~1–2 days). Land it as a behavior-preserving refactor with the fixture green. Its first commit should be the smoke matrix *failing* for `BUNDLE` on all eight Group A rows — that failure list is the epic's real definition of scope.
3. **Vertical spike** (~a day, after DP) — one hardcoded two-package entitlement written directly into `subscriptions.bundle_entitlement`, `Bundle.Access` implemented for `plan_has_access?/3` and `api_call_limits/2` only, and `:bundle` clauses filled in at just those sites. Prove that a seeded bundle subscription gets exactly the right access and quota with the fixture unchanged. That validates the §5 design end-to-end before any Stripe, package-definition, or UI work.

In parallel, **task A** can proceed independently, and it should lead with the four items that cause rework: data windows, queries/signals per package, the hour/minute rule, and the base quota vs `sanapi_pro`'s existing 600k.

---

## 14. Deferred: unifying the two access models

Recorded so the context is not lost, and explicitly **out of scope** (§11).

The access layer currently holds two *mutually inverse* representations of the same relation:

- **Standard plans** — *the item declares its tier* (`meta(access: :restricted, min_plan: [sanapi: "PRO"])`), read via a single compile-time map (`standard_access_checker.ex:86-88`), and plans are compared **ordinally** (`:76-80`). ✅
- **Custom plans** — *the plan declares its items*, as an explicit allow-list with patterns. ✅

Packages are inherently the allow-list form — they are unordered sets, and the ordinal model cannot express "Social but not Development." So this epic necessarily adds a third consumer of the allow-list model while the ordinal model stays.

A cleaner end state is one `%Entitlement{}` value per subscription, threaded through the Absinthe context in place of the `auth.plan` string, with every plan compiling to one. That would delete the prefix dispatch, the `"sanapi_custom_"` branches, `plan_stats/1`, the three `queries/authorization.ex` branches, `restricted_access_as_plan`, `effective_plan_name/2`, and `fetch_base_plan_for_custom/1` — and it would turn "newest subscription wins" (`query.ex:83-89`) from a silent bug into a merge.

Two findings that make it more tractable than it sounds:
- ✅ Only **8 files / 11 sites** read `auth.plan` from the context.
- ✅ `get_available_metrics_for_plan/3` (`standard_access_checker.ex:94-103`) *already* converts a standard plan into an allow-list by filtering all items through `plan_has_access?/3`. Migrating the legacy ladder is largely a **derivation from existing compile-time data**, not hand-transcription.

And the cost that makes it a separate epic:
- The ordinal model's real virtue is that **a new metric lands in the right plans automatically** — the moduledoc says so (`standard_access_checker.ex:6-7`). Flip to plan-declares-items and every new metric across ~1046 needs a per-package decision, forever. Defining packages as category **rules** rather than frozen snapshots mitigates it but does not remove it.
- The `BUNDLE` design in §5 does not block this. If task **EN** produces a real `%Bundle.Entitlement{}` struct (as specified) rather than a `Restrictions` map, that struct is the seed of the unified model, and this epic is a step toward it rather than away from it.

---

## Appendix: verification log

Read directly at `c7754293a`. Anything not listed here is ⚠️ inference or an open decision.

| Claim | Site |
|-------|------|
| Access dispatch by `"CUSTOM_" <> _` prefix | `lib/sanbase/billing/plan/access_checker.ex:28-33`, `:50-63` |
| `Restrictions` embedded schema fields | `lib/sanbase/billing/plan/custom_plan/custom_plan_restrictions.ex:6-16` |
| `query_access` / `signal_access` are required | same file, `:28`, `:33` (`@required_fields` + `validate_required`) |
| `month > hour > minute > 0` validation | same file, `:56-70` |
| Entitlement façade (6 functions) | `lib/sanbase/billing/plan/custom_plan/custom_plan_access.ex` |
| Loader raises `MatchError` on missing plan | `lib/sanbase/billing/plan/custom_plan/custom_plan_loader.ex:16-19`, `:60-73` |
| `persistent_term` "not updated" contract | same file, `:12-15`, `:37-58` |
| Quota dispatch by `"sanapi_custom_" <> _` | `lib/sanbase/api_call_limit/api_call_limit.ex:513`, `:541` |
| `sanapi_pro` = 600k/month | `lib/sanbase/api_call_limit/restrictions.ex:8-13` |
| Response-size limits only for trialing/free | `lib/sanbase/api_call_limit/api_call_limit.ex:397-401`, `:560-566` |
| `plan_stats/1` has no catch-all | `lib/sanbase/billing/plan/standard_access_checker/sanbase_access_checker.ex:62-73` |
| **`Plan.plan_name/1` has no catch-all** (runs on every request) | `lib/sanbase/billing/plan.ex:143-149`; `@same_name_plans` at `:131-141` |
| 4 window functions have no catch-all | `standard_access_checker/api_access_checker.ex:68-79`, `:81-88`, `:98-109`, `:111-118` |
| `query_executions_limit/2`, `credits_limit/2` have no catch-all | `lib/sanbase/queries/authorization.ex:123-155`, `:157-189` |
| `user_plan_to_dynamic_repo/2` catch-all → `FreeUser` | `lib/sanbase/queries/authorization.ex:~95-120` |
| Credits / query-execution limits handle `CUSTOM_` | `lib/sanbase/queries/authorization.ex:114`, `:151`, `:185` |
| 4 plan dispatch sites in `AccessChecker` (all with `_ ->` fallback) | `lib/sanbase/billing/plan/access_checker.ex:27`, `:49`, `:91`, `:127` |
| Nil quota → `ArithmeticError` one frame later | `lib/sanbase/api_call_limit/api_call_limit.ex:541-556` → `:478-496` |
| `plans_enum` has no `bundle` value | `lib/sanbase_web/graphql/schema/types/metric_types.ex:17-25` |
| `restrictions.ex` has no plan dispatch of its own | `lib/sanbase/billing/plan/restrictions.ex` (delegates via `AccessChecker`) |
| Standard access is ordinal, from a compile-time map | `standard_access_checker.ex:76-80`, `:86-88`; moduledoc `:6-7` |
| Legacy plan → allow-list converter already exists | `standard_access_checker.ex:94-103` |
| Only 8 files / 11 sites read `auth.plan` | `document_provider.ex`, `request_halt_plug.ex`, + 6 resolvers |
| Sanbase fallback via `restricted_access_as_plan`; dead `{:error, _}` branch | `lib/sanbase/queries/authorization.ex:192-204`, `lib/sanbase_web/graphql/plugs/auth_plug.ex:350-358` |
| `effective_plan_name/2` runs per request; items not preloaded | `auth_plug.ex:350-362`, `subscription.ex:32` |
| Newest sub wins (`order_by: [desc: id], limit: 1`) | `lib/sanbase/billing/subscription/query.ex:83-89` |
| `has_active_subscriptions/2` is per-`plan.id` | `lib/sanbase/billing/subscription/subscription.ex:594-599` |
| Upgrade rewrites item[0] | `lib/sanbase/stripe/stripe_api.ex:201-215` |
| `fetch_plan_id/2` overwrites `plan_id` from item[0] | `lib/sanbase/billing/subscription/subscription.ex:752-757` |
| Webhook resolves plan from item[0] | `lib/sanbase/billing/stripe_event.ex:148-155` |
| Other `hd()`/`first()` sites | `stripe_sync.ex:66`, `timeseries.ex:239`, `stripe_api.ex:287` |
| ~13 `access: :restricted` GraphQL queries | `lib/sanbase_web/graphql/schema/queries/` (`historical_balance_queries.ex:114`, `blockchain_metric_queries.ex`, `social_data_queries.ex`) |
| `available_metrics.ex` has no plan/subscription awareness | `lib/sanbase/available_metrics/available_metrics.ex` (no matches for `plan`, `subscription`) |
| `getAvailableMetrics` takes `plan` as an argument | `lib/sanbase_web/graphql/resolvers/metric/metric_resolver.ex:62-78` |
| `plan_name` exposed from the **DB** plan | `lib/sanbase_web/graphql/resolvers/billing_resolver.ex:395`, `billing_types.ex:52` |
| Mapping rows are single-category but repeatable per metric | `lib/sanbase/metric/category/metric_category_mapping.ex:34-49` |
| `subscription_items` table does not exist | no matches in `lib/`, `priv/` |
| Existing characterization tests | `test/sanbase/billing/metric_access_level_test.exs` (1831 lines), `query_access_level_test.exs` (242 lines) |
