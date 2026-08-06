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
4. **The product model in the original write-up is missing two dimensions** the code forces you to answer: data windows (historical depth / realtime cutoff) and query/signal access. ✅ Both are now settled — windows are uniform full history (§5.7), and queries/signals are `"all"` for every bundle because they are already effectively unrestricted (§6.4). Neither needs product input; both still need to be written explicitly.
5. **Two of the original "open questions" are answered by the code.** Package prices must *not* become rows in `plans` (§7.3 #2); hour/minute rate limits must *not* be summed (§6.2). See §9.
6. **Do Stripe last, not first.** The catalog is cheap and reversible; entitlement semantics are not. See §8.
7. **§15 is the running list of questions for product**, written in plain language for a non-engineer. Every decision the build needs goes there; answers move up into §9. Send product that section, not this document.

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

### 1.1 Pricing page: three commercial columns

The public "Pricing & Packages" surface (mock; amounts provisional) is **not** packages-only. It has three columns that map to different billing models:

| Column | Product name | Commercial model | Billing model in this epic |
|--------|--------------|------------------|----------------------------|
| Left | **API · by data type** | Pick 1..N of 5 data packages (+ optional API-call add-on). Full history, 100k req/mo base, MCP. | **`BUNDLE`** — multi-item entitlement path (tasks PD…SL) |
| Middle | **Institutional · flagship** | Fixed SKU: Full Sanbase + Full SanAPI + MCP. 3 seats, 50k req/mo, 3-year history. ~$799/mo · ~$9,500/yr. | **`INSTITUTIONAL`** — fixed standard plan (task **IN**) |
| Right | **Enterprise · custom** | Sales-led: Institutional baseline + full history all pillars + S3 + 300k calls + dedicated AM / DPA. From ~$19,999/yr. | **`CUSTOM_*` / sales** — not self-serve cart (task **EP**) |

**Prices are not final** and must stay changeable (catalog data + Stripe Price replace — §9). Provisional figures from the mock do not block implementation; only the *list of SKUs / plan shapes* does.

⚠️ Do not model Institutional as "a BUNDLE with all five packages." Quota (50k vs 100k) and history (3y vs full) already diverge; seats and Sanbase inclusion are further differences. See task **IN**.

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
- **`getAvailableMetrics(plan:, product:)`** — ✅ `plans_enum` includes `bundle`. Catalog browse uses `metricPackages` (required for `BUNDLE`); AccessChecker entitlement path exists for callers that already hold one. Non-bundle plans unchanged.
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

1. **Every sku needs both variants.** Each package price and each extra-calls add-on must exist in monthly *and* yearly form, or a monthly subscriber cannot buy an add-on that only exists yearly. So `interval` is a first-class column on the price catalog, and the purchase UI must filter available skus by the subscription's existing interval. Catalog size is `(5 packages + N call tiers) × 2`.
2. **Switching monthly ↔ yearly is not an add/remove-item operation.** It swaps *every* item to its counterpart price and repoints `subscriptions.plan_id` at the other `BUNDLE` row. Stripe can do it in one update with proration, but the local sync has to move `plan_id` too — otherwise the subscription claims an interval its items no longer have. Task **SL** owns it as a distinct mutation.
3. **Validate at subscribe and at add-item.** Reject a mixed-interval cart before calling Stripe rather than surfacing a Stripe error, and reject adding a yearly package to a monthly subscription. The webhook sync should also flag a mixed-interval subscription if one ever appears, rather than silently resolving an entitlement from it.

✅ **Decided: a package includes full history. There is no history add-on in v1.**

That makes the window **global and uniform** for every bundle:

| Field | Value | Why |
|---|---|---|
| `historical_data_in_days` | `nil` | `nil` means no restriction (`custom_access_checker.ex:36-39`) |
| `realtime_data_cut_off_in_days` | `0` | Paid plans get realtime; only FREE is cut off at 30 days |

Two consequences worth knowing:

- **The window dimension effectively drops out of v1.** ✅ SanAPI `PRO` already has `historical_data_in_days: nil` and `realtime_data_cut_off_in_days: 0` (`api_access_checker.ex:39-45`), so a bundle differs from PRO only in *which metrics* and *how many calls* — not in depth. `EN` keeps the two flat fields from §5.3 and never needs a per-grant list.
- **Keep the fields, don't design them out.** They cost nothing (the `Restrictions`-shaped output needs them anyway) and a future per-pillar add-on becomes a resolver change rather than a schema change. If the window ever does become per-grant, the stored blob's shape changes — that is exactly what `schema_version` in §5.3 is for, so it is a bump plus a backfill, not a migration scramble.

⚠️ **This makes Institutional's "3-year history" indefensible.** If a $350 Market package includes full history, then buying five individual packages gives *more* depth than the $799 Institutional tier that contains all five. Either Institutional is also full history — recommended, and then depth is uniform everywhere and truly stops being a dimension — or single packages are not. Raise it on the call; it is a pricing fix, not a code one.

---

### 5.8 How a bundle's entitlement reaches the code that needs it

This is the one hole in §5.4 that had to be closed before any code. §5.4 says *where the entitlement is stored*; it never said *how the functions that answer access questions get hold of it*.

**The problem.** Every function that decides access takes the plan **name** and nothing else:

```elixir
def plan_has_access?(query_or_argument, requested_product, plan_name)
```

For a per-customer plan this is enough, because the name identifies the customer — `CUSTOM_ACME` is one row, one restrictions blob, so `Loader.get_data(plan_name, product)` can find it. That is the load-bearing property of the `CUSTOM_*` design, and `BUNDLE` gives it up on purpose: ✅ every bundle subscription shares the single name `BUNDLE` (§5.7), so the name identifies *nothing*. `plan_has_access?({:metric, "price_usd"}, "SANAPI", "BUNDLE")` has nothing to look up.

⚠️ Note the consequence for §8 **BA** as originally written: "six functions mirroring `CustomPlan.Access`" cannot work unchanged, because those signatures cannot reach a per-subscription value.

**What already exists.** ✅ `auth_plug.ex:206-211` puts the whole subscription into the request context:

```elixir
auth: %{auth_method: :user_token, current_user: current_user,
        subscription: subscription, plan: effective_plan_name(subscription, "SANBASE")}
```

✅ It is `access_control.ex:648-660` (`context_to_plan_name_product_code/1`) that reduces it to a plain string on the way to the access checker. The data is already there; only the last hop drops it. Adding the column to the subscription row (§5.4) makes it available for free, since AuthPlug already loads the row.

**Decision: pass the entitlement as an extra, optional argument.**

```elixir
def plan_has_access?(query_or_argument, requested_product, plan_name, entitlement \\ nil)
```

- The `:standard` and `:custom` branches **ignore** it. Only the `:bundle` branch reads it.
- ✅ Every existing caller keeps calling the three-argument form and is unaffected — including the BC characterization fixture, which is what makes this provably safe rather than merely believed safe.
- The bundle branch **raises** on `nil` rather than falling back to the standard ladder. A missing entitlement is a bug, and §7.5 B1 is the reason: silently answering from the ordinal ladder gives a paying customer roughly FREE access with no error anywhere.

**Quota needs a different answer.** ✅ There is no subscription in scope where limits are computed — `get_api_calls_maps/1` derives them purely from the `api_calls_limit_plan` string on the `api_call_limits` row (`api_call_limit.ex:481`), and that string is `"sanapi_bundle"` for every bundle customer alike. So the resolved numbers are **written onto the `api_call_limits` row** when the subscription syncs. ✅ That row already carries per-user overrides (`has_limits_no_matter_plan`, `has_limits` — `api_call_limit.ex:39-41`), so this fits the existing design rather than fighting it, and it is the same "resolve once at sync, store on the row" pattern as §5.4.

**Rejected: naming plans `BUNDLE_<subscription_id>`.** It would mirror `CUSTOM_*` exactly and need *zero* signature changes — ✅ `Plan.type/1`'s prefix match already accepts it. Tempting, and rejected for two reasons: a `plans` row per subscription turns a small catalog into a per-customer table, and reusing `CustomPlan.Loader` for it would put a customer-triggered write into `:persistent_term`, which is the exact hazard §10 warns about.

**Relationship to §14.** This is a small step *toward* the deferred unification, not away from it. §14's end state is one entitlement value per subscription carried in the context instead of the `auth.plan` string. Threading it as an optional argument is that same value arriving at the same functions — just alongside the plan name rather than replacing it. Nothing here has to be undone later.

---

### 5.9 Everything that is *not* access or quota: a bundle behaves like PRO

Two things come from the entitlement, because they are what the customer chose:
which metrics they may read, and how many API calls they get. **Everything else
has no per-package answer and needs one anyway** — how many alerts they can
create, how much query credit they get, which ClickHouse repo their queries run
against, how a query's complexity is scored, and their whole Sanbase experience.

✅ **Decided by product (§15 Q5):** the same as a SanAPI PRO customer who has no
Sanbase subscription. Bundles are priced against PRO, so PRO is what they get.

One definition, `Sanbase.Billing.Plan.Bundle.equivalent_standard_plan/0`, used in
six places:

| Site | Why it needs it |
|------|-----------------|
| `AuthPlug.effective_plan_name/2` | A Sanbase request falls back to a SanAPI subscription, so `"BUNDLE"` would otherwise reach Sanbase access checks and let a package's metric list decide Sanbase access |
| `SanbaseAccessChecker` plan stats | alerts limit and the rest of the Sanbase allowances |
| `Queries.Authorization.credits_limit/2` | query credit |
| `Queries.Authorization.query_executions_limit/2` | how many queries |
| `Queries.Authorization.user_plan_to_dynamic_repo/2` | which ClickHouse repo |
| `Graphql.Complexity` | how expensive a query is scored |

This is the same treatment `CUSTOM_*` plans already get through
`restricted_access_as_plan` / `fetch_base_plan_for_custom/1`, and for the same
reason: an API-specific metric allow-list must not leak into decisions that are
not about metrics.

⚠️ **`Graphql.Complexity` was missed by the §7.5 inventory.** It runs in Absinthe's
*document phase*, not through `AccessChecker`, so neither the inventory nor the
`Plan.type/1` dispatch test found it — and its `case plan.name` has no catch-all.
The first real GraphQL request from a bundle subscriber raised `CaseClauseError`
there, before any access or quota code ran. It is fixed and pinned by a test now,
but the lesson generalises: **the dispatch inventory only covers sites reachable
through `AccessChecker`.** Anything that pattern-matches a plan name elsewhere —
document phases, plugs, LiveViews, background jobs — is outside it. A real
end-to-end request is the only thing that finds those.

### 5.10 The call quota: resolved numbers on the `api_call_limits` row

The quota path had the same problem as the access path, in a worse position. It
runs on **every** API request, and it asks for limits by plan name —
`plan_to_api_call_limits("sanapi_bundle")`. Every bundle carries that one name
while the numbers differ per customer, so the name cannot answer.

Unlike the access path, this one could not be fixed by threading an argument: the
quota check reads an `api_call_limits` row and has no subscription in hand. So the
numbers are resolved when the subscription syncs and **stored on the row**, in
`resolved_api_call_limits` (jsonb, nullable).

| | |
|---|---|
| **Written by** | `ApiCallLimit.update_user_plan/1` and the row-creation path, both from `user_to_plan_state/1` |
| **Read by** | `ApiCallLimit.acl_to_api_call_limits/1`, which the quota path calls with the row it already holds |
| **Refreshed by** | `Bundle.Resolver.sync/1`, after its transaction commits |
| **`nil` means** | derive from the plan name — what every non-bundle row holds, and the reason this is invisible to existing customers |

Three properties worth keeping:

* **`nil` is written explicitly for non-bundle plans**, so a customer who moves off
  a bundle does not keep its allowance. A stale value here would be a billing bug.
* **A stored value is ignored unless the plan is a bundle.** The plan name decides
  which branch runs; the column is only consulted inside it.
* **A bundle row with nothing stored raises** rather than falling back. It means the
  subscription never synced, and any invented number either refuses a paying
  customer or gives away calls — both of which look like a working configuration
  from the outside.

`plan_to_response_size_limits/1` needed none of this: response size is not sold per
package (§6.2), so a bundle answers as `equivalent_standard_plan/0` like everything
else in §5.9.

⚠️ **`ApiCallLimit.Sync` cannot detect drift in these numbers.** It reconciles rows
by comparing plan *name* and status (`expected_plans_bulk/0`), and a bundle whose
items changed still reports `sanapi_bundle`. The live path is covered —
`Resolver.sync/1` rewrites the row — but if an entitlement is ever changed without
going through it, the reconciler will not notice. Worth extending when **WH**
(webhook handling for multi-item subscriptions) lands and Stripe becomes a second
writer.

### 5.11 The lifecycle: buying, changing and leaving a bundle

`Bundle.Lifecycle` is the one door for all of it — subscribe, add an item, remove
an item, switch billing interval, cancel. Everything it does ends in
`Resolver.sync/1`, so the entitlement and the quota row are recomputed from the
items rather than adjusted in place.

| Operation | Stripe | Local | Entitlement |
|---|---|---|---|
| `subscribe/2` | creates the subscription with one item per price | inserts the subscription and its items | resolved for the first time |
| `add_item/3` | adds an item, prorated | claims the row first, then writes the Stripe id onto it | package available at once |
| `remove_item/3` | **nothing yet** | records `remove_at` on the item | unchanged — the customer paid for this period |
| `switch_interval/2` | re-prices every item by id, deletes those leaving | moves `plan_id`, refreshes item ids, deletes those leaving | unchanged |
| `cancel/2` | `cancel_at_period_end` | synced from the response | unchanged until the period ends |
| `ItemExpiry.run/1` (hourly) | deletes items past `remove_at`, no proration | deletes the rows | package finally goes away |

Four rules hold this together, and each is the answer to a way it went wrong:

* **Removal is a date, not a flag.** `subscription_items.remove_at` holds the
  moment the item is due to go. A boolean cannot say *which* period end was meant,
  and a subscription's `current_period_end` jumps forward the instant Stripe
  renews — so "items whose subscription's period has ended" finds nothing once the
  renewal is synced, and the item is billed forever.
* **Stripe item ids are never invented.** An item with no id from Stripe stores
  `nil`, not a synthetic string. `switch_interval` sends `id` plus `price` for
  every item it keeps and `deleted: true` for every item it drops, because an
  entry without an `id` tells Stripe to **add** another item, and items missing
  from the array are not removed. Losing the real ids once means the next switch
  bills the customer on both intervals.
* **Whatever charges, compensates.** Money moves before the local state is
  written. Any failure after the Stripe subscription is created cancels it with
  proration and reports; if even that fails, it is a Sentry alert naming the
  `stripe_id`, because a human then has to refund it. Everything checkable without
  charging — a published snapshot, sellable prices, a usable coupon, the plan row —
  is checked first.
* **Nothing is decided by a read that two requests can both pass.** `add_item`
  inserts the local row before calling Stripe, so the unique index on
  `(subscription_id, sku)` settles a race and only the winner creates a Stripe
  item. Two simultaneous `subscribe` calls both land, and the one with the higher
  id withdraws itself — lowest id wins, so exactly one survives whichever order
  they finish in.

⚠️ **`remove_item/3` depends on a scheduled job.** If
`expire_bundle_subscription_items` stops running, removals never happen: the
customer keeps the package and keeps paying for it, with nothing in the API
looking wrong. `cancel_stale_replaced_subscriptions` is the same shape — it is what
catches a legacy `BUSINESS_PRO` that failed to cancel during a bundle purchase, and
without it that customer pays for both.

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
| **Data windows** (`historical_data_in_days`, `realtime_data_cut_off_in_days`) | **Global, uniform**: `nil` history + `0` realtime cut-off. A package includes full history; no add-on in v1 | ✅ **decided** (§5.7) |
| **API calls** | month: **sum** of package bases + add-ons. hour/minute: **do not sum** — see below | partially specified |

**Queries and signals are a required *field*, but not a per-package decision.** There are 13 `access: :restricted` GraphQL queries and 10 signals, and they do map onto the packages being sold — top-holders and historical-balance functionality is core Onchain Labels surface and lives in **queries**, not the metric registry.

⚠️ **Corrected after verification:** an earlier draft of this section concluded that a metric-only package would under-deliver Onchain Labels and Social. That is wrong. `access: :restricted` means *window-limited*, not paywalled, and 12 of the 13 queries plus all 10 signals are reachable by a free user today. So a metric-only package under-delivers nothing — but the entitlement must still say `"all"` explicitly, because the allow-list denies by default. See §6.4 for the inventory and the reasoning.

**Data windows — resolved, and deliberately so.** `nil` means *no restriction* (`custom_access_checker.ex:36-39` docstring), which is normally a trap: leaving the field unset silently ships full history and full realtime. Here it is the intended answer — a package includes full history (§5.7). Worth stating explicitly rather than leaving implied, because "we forgot to set it" and "we chose not to restrict it" produce identical code and very different conversations later.

**Do not sum hour/minute limits.** `validate_api_calls` requires `month > hour > minute > 0` (`custom_plan_restrictions.ex:56-70`). Summing per-package rate limits makes burst capacity scale with *entitlement breadth*, but rate limits exist to protect infrastructure, not to price data. Recommend: **sum month; take max (or a fixed base-plan value) for hour and minute.** ✅ verified.

**Sanity-check the quota pricing.** `sanapi_pro` is already **600k/month** (`api_call_limit/restrictions.ex:10`). At 100k per package, all five packages = 500k — *less* than today's PRO, presumably at a higher total price. Either the 100k base is too low or the add-on is effectively mandatory. ⚠️ Resolve in task **A** before any Stripe price exists.

**Minor:** response-size limits only apply when status is `trialing` or plan is `sanapi_free` (`api_call_limit.ex:397-401`), and `CustomPlan.Access.response_size_limits/2` is a hardcoded TODO (`custom_plan_access.ex:12-17`). So a *trialing* bundle sub would get a 200,000 MB/month allowance — effectively unlimited. Harmless, but note it if bundles get trials (task **TR**).

### 6.3 Rules (recommended)

1. Metric / query / signal access = **union** of purchased packages
2. Monthly API call limit = **flat 100,000 + add-ons**. ✅ Decided by product: *not* summed per package. `EN` never reads the package list to compute quota (§9)
3. One **shared** call bucket (never split Social vs Onchain rate limits)
4. Hour/minute limits from a **single base value**, not summed — reuse `sanapi_pro` (30k/hour, 600/minute) as burst protection (§9)
5. Data windows = **uniform**: full history (`nil`) and no realtime cut-off (`0`) for every bundle (§5.7)
6. One Stripe subscription, many items, one invoice (Stripe native)
7. Prefer composition of prices over combinatorial fixed combo SKUs
8. Plan naming: `plans` rows named `BUNDLE` on SanAPI (one per interval) as markers; the entitlement comes from the items (§5.0, §5.7)
9. Queries and signals = **`"all"` for every bundle** (§6.4)

### 6.4 Queries and signals: the inventory, and why they need no per-package split

⚠️ **`access: :restricted` does not mean paywalled.** It means *time-window limited*. Plan gating is a separate `min_plan` key, and ✅ the default when it is absent is `"FREE"` (`standard_access_checker.ex:87`).

Consequence: of the 13 restricted queries, **exactly one is actually plan-gated** — `miners_balance` at `[sanapi: "PRO", sanbase: "FREE"]` (`historical_balance_queries.ex:114`). The other 12 are reachable by a free API user today, with only the history window varying. ✅ And all 10 signals are `access: free` on both products (`lib/sanbase/signal/signal_files/available_signals.json`).

| Social (7) | On-Chain Labelled (5) | On-Chain (1) |
|---|---|---|
| `get_trending_words`, `get_trending_stories`, `get_word_trending_history`, `get_project_trending_history`, `word_context`, `words_context`, `words_social_volume` | `top_holders`, `realtime_top_holders`, `top_holders_percent_of_total_supply`, `top_exchanges_by_balance`, `miners_balance` ← the only paid one | `gas_used` |

Nothing maps to **Market** or **Developer** — those two packages are metrics-only.

Signals: `mvrv_usd_{{timebound}}_upper_zone`, `mvrv_usd_{{timebound}}_lower_zone`, `anomaly_project_in_trending_words`, `anomaly_total_liquidations`, `anomaly_eth_whale_dump`, `anomaly_hyperliquid_avg_funding_rate`, `anomaly_large_stablecoin_mint`, `anomaly_social_price_correlation`, `anomaly_social_dominance_spike`, `anomaly_price_network_activity_divergence`.

**Therefore `query_access` and `signal_access` are `"all"` for every bundle.** Enumerating them per package would make a paying bundle customer *lose* queries a free user has today — a regression, not a feature. `miners_balance` comes along with `"all"`, which is correct: bundles are paid plans priced around PRO, and PRO has it.

🔴 **But "unrestricted" still has to be stated explicitly.** The allow-list denies by default, and ✅ `query_access` / `signal_access` are in `@required_fields` (`custom_plan_restrictions.ex:28`, `:33`). A resolver that leaves them `nil` instead of `"all"` breaks *every* query and signal for bundle customers. ✅ `"all"` is already a first-class value in the loader (`custom_plan_loader.ex:124`, `:135`), so it is reuse, not new code — but **task EN needs an explicit test asserting both fields resolve to the full item set**, precisely because "no restriction" is the kind of answer that gets implemented as an omission.

⚠️ If queries should later become a per-package selling point (Social's trending words only for Social buyers), decide it **before launch** — tightening access for existing customers is the expensive direction.

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
| 3 | `stripe_event.ex:150-155` `handle_subscription_created/3` | Resolves the plan from item[0] via `Plan.by_stripe_id/1` and errors `{:plan?, _}` if not found. Stripe does not guarantee item order, so a bundle sub either fails to sync or binds to the wrong plan. Observed on stage: event stuck at `is_processed: false`, logging "Plan for subscription_id … does not exist". | ✅ **done (WH)** — `ItemSync.bundle_stripe_subscription?/1` matches the item price ids against `bundle_prices` (any match wins) and branches before the plan lookup. The marker plan comes from `Plan.bundle_plan(interval)`, never from an item. |
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
| **C1** | `metric_types.ex` `enum :plans_enum` | ✅ `bundle` added; catalog browse requires `metricPackages` | Done in task **AM** |
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

### PD. Package definition & snapshot — ✅ done
**Implemented as:** `Bundle.Package` (rules) + `Bundle.PackageSnapshot` (materialize / publish / `pending_changes` / `metrics_for`) + `bundle_package_snapshots`. Snapshot chosen over live, as recommended. The admin diff *screen* is not built; `pending_changes/0` is the logic behind it. Templates are expanded to concrete metric names, deprecated and hidden metrics are excluded, and a missing category refuses the build rather than selling an empty package. See §13.0 for the one unverified assumption.

**What:** The source of truth for what each package contains (metrics + queries + signals). Split out of A because it is a correctness and contractual concern, not a config detail:
- `metric_category_mappings` is edited continuously by admins in the categorization LiveView. If access reads **live** category membership, an admin re-categorizing one metric silently **grants or revokes** access a customer paid for.
- ✅ The schema has singular `category_id` / `group_id` per row (`metric_category_mapping.ex:42-43`) but a metric may have **multiple** rows, and the Notion task explicitly wants dual membership. A metric in both Onchain Core and Onchain Labels is therefore sellable via either. Fine for a union — but needs a **leak check** that a Market-only buyer cannot pick up Onchain metrics through a second mapping row.

**Recommendation:** define packages as category/group **rules**, materialize to a **versioned snapshot** with a diff preview in admin before publish, and pin each subscription to a snapshot version.
**Deliverable:** package definition module + snapshot table + admin diff view + leak-check test.
**Depends on:** A. ⚠️ Snapshot-vs-live is a real trade-off; live is defensible if you accept that admin category edits *are* billing changes and gate the LiveView accordingly.

### LC. Local multi-item subscription model — ✅ done
**Implemented as:** `subscription_items` (+ `Subscription.Item`), `bundle_prices` (+ `Bundle.Price`), and the two `BUNDLE` marker rows (ids 301/302, SanAPI, amount 0, `is_private`, **not** `has_custom_restrictions`). Item SKUs are validated against the package and add-on definitions on the way in, so a typo cannot be stored and then silently grant nothing. `bundle_prices.amount` is nullable on purpose — prices are not final, and `Price.sellable/1` excludes rows that cannot yet be charged. `Price.replace/1` deactivates and re-inserts, because Stripe Prices are immutable.

⚠️ **One behavior change outside the bundle path:** `Plan.product_with_plans/0` now excludes `BUNDLE%` rows. Without it, adding the marker rows would put a $0 plan named `BUNDLE` on the public `productsWithPlans` response and offer `subscribe(plan_id:)` a plan it cannot correctly create. With it, that response is unchanged from before this epic.

**What:** Create the `BUNDLE` plan rows (markers only, one per interval — **not** `has_custom_restrictions: true`; see §5.7 and §7.5 C2). Keep `subscriptions.plan_id` pointing at it. Add `subscription_items` (`stripe_item_id`, `sku`/`price_id`, `quantity`, `type: :package | :api_calls`), a **price catalog table** (not `plans` rows — see §7.3 #2), and `subscriptions.bundle_entitlement` JSONB (§5.4).
**Deliverable:** migration + schemas + sync helpers.
**Depends on:** A. **Not** on the Stripe catalog — seed from fixtures/admin so everything downstream can be built and tested before a Stripe object exists.
**BC:** legacy subs have no `subscription_items` rows and `bundle_entitlement IS NULL`.

### EN. Entitlement resolver (core) — ✅ done
**Implemented as:** `Bundle.Resolver.resolve/2` (pure: items + snapshot → entitlement attributes) and `Bundle.Resolver.sync/1` (loads items and the latest snapshot, resolves, writes the row). `sync/1` recomputes from scratch every time, so the several `subscription.updated` events one item change produces are harmless — which is what **WH** needs.

Two deliberate refusals: a subscription with no package item, and an add-on with no package behind it. Both would otherwise produce an entitlement that grants nothing, which is indistinguishable from a working one everywhere downstream and presents as a paying customer whose every request is refused.

One correction to the original description: monthly calls are **not** summed per package. Product decided a flat 100,000 plus add-ons (§9), so the resolver never reads the package list to compute quota.

**What:** `items + package_defs -> %Bundle.Entitlement{}` (§5.3). Union metrics/queries/signals, sum monthly calls, apply the window and rate-limit rules from A. Pure function — no DB, no cache, fully unit-testable. Plus the writer that persists it to `subscriptions.bundle_entitlement` and the `schema_version` / `package_snapshot_version` handling.
**Deliverable:** struct + resolver + persistence + unit tests with fixtures.
**Depends on:** A, PD, LC.

### BA. Bundle access path — ✅ done
**Implemented:** `plan_has_access?`, `historical_data_in_days`, `realtime_data_cut_off_in_days`, `api_call_limits`, and `get_available_metrics_for_plan` on `Bundle.Access`. All access functions take the optional entitlement argument of §5.8, and the entitlement is threaded from the request context through `AccessControl` and `Plan.Restrictions.get/5` (which the metric and signal resolvers use — without it a bundle customer would get a 500 on metric metadata). The shared-access-token path needs nothing: `token.plan` is hardcoded to `"PRO"` (`shared_access_token.ex:108`), so it can never carry a bundle. `bundle_entry_points/0` is empty.

**What:** The new path itself. `Bundle.Access` — six functions mirroring `CustomPlan.Access` (`plan_has_access?`, `get_available_metrics_for_plan`, `api_call_limits`, `historical_data_in_days`, `realtime_data_cut_off_in_days`, plus whatever C2 decides for Sanbase) reading the stored entitlement. Then fill in the `:bundle` clause at **every** site from §7.5 groups A and B, replacing the `"not implemented"` raises from **DP**.

⚠️ **Not a straight mirror of `CustomPlan.Access`** — see §5.8. Those signatures take only a plan name, which cannot identify a bundle customer. The access functions gain an optional entitlement argument, and the quota functions read numbers stored on the `api_call_limits` row instead.
**Deliverable:** `Bundle.Access` + ~20 one-line dispatch clauses + tests per site.
**Depends on:** EN, DP. **Highest-risk task in the epic.** Acceptance: the §7.6 smoke matrix is green for `BUNDLE` and the **BC** fixture is unchanged.

### SC. Stripe catalog — ✅ done
**Implemented as:** `Bundle.Catalog` (`ensure_local_catalog/0`, `sync_with_stripe/0`) exposed as `Sanbase.Billing.sync_bundle_catalog_with_stripe/0` and included in `Sanbase.Billing.sync_products_with_stripe/0` (`@reboot` on stage/prod). Twelve local `bundle_prices` rows (5 packages + `api_calls_500k` × month/year). Packages get provisional amounts from the pricing mock; `api_calls_500k` stays `amount: nil` until product prices it. Sync creates one Stripe Product per SKU (metadata `sanbase_sku`) and recurring Stripe Prices (modern Price API, not legacy Plan), then writes `stripe_price_id`. Idempotent; skips nil-amount and already-linked rows. Seed script calls `ensure_local_catalog/0` (local only).

**Provisional amounts (from pricing page mock; changeable — never hardcode charging logic):**

| SKU | Type | Month | Year |
|-----|------|------:|-----:|
| `market` | package | $350 | $3,500 |
| `social` | package | $700 | $7,000 |
| `development` | package | $350 | $3,500 |
| `onchain_core` | package | $400 | $4,000 |
| `onchain_labels` | package | $400 | $4,000 |
| `api_calls_500k` | api_calls | ⚠️ TBD | ⚠️ TBD |

Changing a priced amount after Stripe exists = `Price.replace/1` + new Stripe Price + archive old. Setting the add-on amount + re-running sync makes it sellable.
**Deliverable:** ✅ local catalog + Billing module sync path + mocked tests. Live Stripe objects appear on `@reboot` or remote iex `Billing.sync_bundle_catalog_with_stripe/0`.
**Depends on:** A, LC.
**Does not include:** Institutional / Enterprise Stripe prices — those are **IN** / **EP**.

### SL. Subscribe / add / remove / cancel — ✅ done
**Implemented as:** `Bundle.Lifecycle` + GraphQL `subscribeBundle` / `addBundleItem` / `removeBundleItem` / `switchBundleInterval` / `cancelBundleSubscription`. Stripe multi-item create via Price ids; local `subscription_items` + `Resolver.sync/1` after each mutation. `upgrade_downgrade/2` rejects bundles. Legacy `subscribe` rejects `BUNDLE` marker plans only — `is_private` is deliberately not a gate, since `PRO`, `PRO_PLUS`, `MAX` and `FREE` are all `is_private = true` on production and bought through it every day (§15 Q14).

**Sale controls:** `Sanbase.Billing.Plan.SaleControls` + admin page `/admin/bundle_offering`. Activate/deactivate **bundle/new plans** (`BUNDLE*`, `INSTITUTIONAL*` via `is_private`) and **Business Pro/Max** (`is_deprecated`). GraphQL `bundleCatalog(interval)` is public when bundle plans are active, or always for Santiment team. Staff can preview/subscribe while bundle plans are deactivated.

**Legacy → Bundle:** create new sub first, then cancel replaceable ladder (`BUSINESS_*`, grandfathered `PRO`/`BASIC`) with Stripe proration. Rejects active `CUSTOM_*` and already-on-bundle. That cancel never fails the paid purchase, so `cancel_stale_replaced_subscriptions/0` retries it hourly as `cancel_stale_replaced_subscriptions` (§5.11).

**Remove item:** `remove_item/3` only records the deadline in `subscription_items.remove_at`; the package keeps working and keeps being billed until it passes, because the customer paid for that period. `Sanbase.Billing.Plan.Bundle.ItemExpiry` — scheduled hourly as `expire_bundle_subscription_items` in `config/scheduler_config.exs` — then deletes the Stripe item with no proration, deletes the local row and re-resolves the entitlement.
**Deliverable:** ✅ GraphQL + Stripe helpers + offering gate + admin Go Live/Rollback + mocked tests.
**Depends on:** SC, LC, BA.
**Does not include:** WH webhook branching; Institutional plan rows (**IN**); purchase UI.

### WH. Webhook / sync for multi-item — ✅ done
**Implemented as:** `Sanbase.Billing.Plan.Bundle.ItemSync` plus three branches in `stripe_event.ex`. A bundle Stripe subscription is recognised by looking its item price ids up in `bundle_prices.stripe_price_id` (`Price.by_stripe_price_ids/1`) — **any** item matching is enough, so a bundle with one unrecognised item can never fall into the legacy path and bind `subscriptions.plan_id` to whatever plan happens to be item[0]. Everything ends in `Resolver.sync/1`, which recomputes the entitlement and the `api_call_limits` row from the item rows, so the several `subscription.updated` events one item change produces are harmless.

| Event | Bundle behavior | Legacy behavior |
|---|---|---|
| `created`, local row exists | reconcile items, re-resolve, mark processed. Nothing is duplicated. | unchanged |
| `created`, no local row | **adopt**: `Plan.bundle_plan(interval)` for the items' interval → `create_subscription_db/3` → one `subscription_items` row per Stripe item → `Resolver.sync/1` | unchanged |
| `created`, any unknown price id | refuses: nothing created, error logged, event left unprocessed | unchanged |
| `updated` | status sync unchanged, then item reconciliation, then `Resolver.sync/1` | unchanged |
| `deleted` | status sync unchanged, then `ApiCallLimit.update_user_plan/1`. Items and entitlement are **kept** — access is already blocked by status and support answers from them. | unchanged |

**Fixes the §7.3 #3 bug seen on stage:** the event used to stay `is_processed: false` with *"Plan for subscription_id … does not exist"*, because `handle_subscription_created/3` read item[0]'s `plan` and looked it up in `plans`. Package prices are only ever in `bundle_prices` (§7.3 #2) and no `plans` row is ever created for one.

**Guards, each preventing a specific failure:**
- **Deactivated catalog rows still resolve.** `Price.by_stripe_price_ids/1` deliberately ignores `is_active`. A price change deactivates the old row but Stripe never re-prices an existing item, so filtering would make every subscription bought before the change look like it held unknown prices — and reconciliation would read the missing SKU as a *removed package*.
- **`stripe_item_id: nil` rows are never deleted.** They are mid-flight claims from `Lifecycle.add_item/3`, which writes the row before calling Stripe so the `(subscription_id, sku)` index settles a race. Deleting one lets a second request create a second Stripe item the customer is billed for.
- **An empty local item set is never populated by reconciliation.** `Lifecycle.subscribe/2` writes the subscription row and *then* its items; a `created`/`updated` event can land in that window. Inserting the items from the webhook would make `persist_items/3` fail on the same unique index — and every post-charge failure in `store_subscription/4` cancels the subscription the customer has just paid for.
- **`remove_at` is preserved.** A scheduled removal stays in Stripe until `ItemExpiry` deletes it, so finding the item in Stripe is not evidence the customer changed their mind. Only `stripe_item_id` and an add-on's quantity are written to a surviving row.
- **Deletion keys on the SKU, not on the item id.** "This row's `stripe_item_id` is absent from Stripe's set" reads the same but deletes a row the repair pass was about to fix when Stripe reissues an item id.
- **A real `stripe_item_id` is never overwritten with `nil`.** Blanking it would make the row indistinguishable from a mid-flight claim, and therefore undeletable.
- **Reconciliation is serialized per subscription** with `FOR UPDATE` on the subscription row, the item set read *inside* that transaction — the same lock and reason as `Resolver.sync/1`. Inserts use `mode: :savepoint` so the one tolerated conflict (a concurrent `add_item/3` claiming the same SKU) does not abort the whole transaction.
- **Unknown price ids: skipped on reconcile, refused on adoption.** Reconciliation maintains a set whose other items are known, so an item it cannot name is left alone rather than deleted or guessed at. Adoption has to write the whole purchased set, and a set with a hole in it is not the purchased set.
- **Adoption checks everything before the first insert** — every price known, one interval, a marker plan for it, at least one package, a published snapshot. A subscription row with no resolvable entitlement is worse than none: the quota path raises on it.

**Deliverable:** ✅ `Bundle.ItemSync` + `Price.by_stripe_price_ids/1` + branches in `stripe_event.ex` + `test/sanbase/billing/stripe_event_bundle_sync_test.exs` (26 tests: 7 legacy BC, 8 `created`, 10 `updated` incl. idempotency, 1 `deleted`).
**Depends on:** LC, EN. **Critical for BC.**
**Not covered:** §7.3 #4 (`stripe_sync.ex`) and #5 (`timeseries.ex`) are separate work — they are first-item *read* assumptions, not the webhook write path.

**One correction to the original description:** it says the `deleted` branch must "reset the `ApiCallLimit` record" because nothing else would. Not quite — `Subscription.update_subscription_db/2` emits `:update_subscription`, and `EventBus.BillingEventSubscriber` already calls `ApiCallLimit.update_user_plan/1` for it, so the quota does drop today. But that path is asynchronous and wrapped in `try/rescue` (`billing_event_subscriber.ex:50-57`), and it is disabled outright in the test config. The webhook now calls `update_user_plan/1` synchronously as well — idempotent, so the two together are harmless, and it is what makes the drop deterministic and testable.

### AM. `available_metrics` by entitlement — ✅ done
**What:** Catalog browse via `getAvailableMetrics(plan: BUNDLE, metricPackages: ["social", ...])` — packages required; resolves from the latest published `PackageSnapshot`. AccessChecker `get_available_metrics_for_plan/4` answers from an entitlement (clears BA). Non-bundle plans unchanged. `plans_enum` includes `bundle` (§7.5 C1).
**Depends on:** EN, BA.

### OB. Admin / support visibility — ✅ done
**Implemented as:** `/admin/bundle_subscriptions` (`SanbaseWeb.Admin.BundleSubscriptionsLive`), with `/admin/bundle_packages` alongside it for the snapshot side. The listing is `Subscription.list_bundle_subscriptions/1` (keyed on the plan *name*, so more marker rows keep working); one row expands into the **resolved** entitlement — packages, effective metric list, query/signal access, the three call limits, the data windows, the derived plan name and the snapshot version — plus the items with their Stripe ids and any `remove_at`. Subscriptions can be created, have items added and removed, and be canceled from there; those rows are **local only, with no Stripe object**, which is deliberate so a support test cannot charge anyone.

Three testers answer the question a ticket actually asks:
- **Decide** — calls the access checker directly for a metric, query or signal, on both products, side by side with a standard plan. Answers "should this customer have this?" with no request and no API key.
- **Scenarios** — generated from the packages the subscription owns, each row carrying its own expectation, so a wrong answer is visible without reading the entitlement.
- **Request** — POSTs to the real `/graphql` with an API key, which is the only one that also proves the plumbing from context to access checker. ⚠️ `@santiment.net` users are exempt from quota (`user_has_limits?/1`), so testing with your own key proves access without exercising the numbers.

**Deliverable:** ✅ two LiveViews + `Subscription.list_bundle_subscriptions/1` / `get_bundle_subscription/1`.
**Depends on:** EN. Small, high value — do not defer it to "later".

### IN. Institutional flagship plan — ⬜ not started
**What:** The middle pricing-page column — a **fixed** SanAPI (+ Sanbase) plan, **not** assembled from packages (Q10). Distinct from `BUNDLE` and from bespoke `CUSTOM_*`.

**Product shape (provisional prices; changeable):**
- **Price:** $799 / mo · $9,500 / yr (⚠️ yearly discount looks wrong vs ~2 months free — Q11)
- **Access:** Full Sanbase + Full SanAPI + MCP
- **Quota:** 50,000 API requests / month (intentional; lower than a single package — §9)
- **History:** 3-year window on API data (confirmed intentional while packages get full history — §9)
- **Seats:** "3 seats" on Sanbase — ⚠️ **Q6** still open; no seats concept exists today
- **Add-ons:** "Add-ons for full history per pillar" — ⚠️ product detail TBD; packages already include full history in v1, so this may mean something else for Institutional

**Implementation shape (recommended):**
- New `plans` rows named `INSTITUTIONAL` (month + year), product SanAPI — same two-row pattern as `PRO`. Likely also Sanbase rows if "Full Sanbase" is sold as part of the same SKU vs a coupled Sanbase sub.
- `Plan.type/1` → `:standard` (or a dedicated `:institutional` atom if we want exhaustiveness separate from PRO) — **not** `:bundle`. No `subscription_items`, no entitlement blob.
- Access via the **standard** path: metric access = all (or equivalent to union of five packages), `historical_data_in_days: ~1095` (3 years), `realtime_data_cut_off_in_days: 0`, `api_call_limits` month = 50_000.
- Stripe: one Product + month/year Prices; wire into existing `subscribe` / plan sync — **not** multi-item SC.
- Exclude from sale coexistence with `BUNDLE` / legacy PRO the same way §7.3 #6 blocks dual SanAPI subs.

**Why not a five-package BUNDLE at $799?** Cheaper to maintain as a fixed plan; Institutional's 3-year history and 50k calls already diverge from "five packages × full history × 100k". Encoding it as packages would fight the product.

**Deliverable:** plan rows + access/quota clauses + Stripe prices + BC fixture still green for FREE/PRO/CUSTOM.
**Depends on:** DP (dispatch seam already landed). Parallel to SC — does **not** block package checkout.
**Open before coding seats / history add-ons:** Q6, and the "full history per pillar add-on" wording.

### EP. Enterprise custom tier — ⬜ not started
**What:** The right pricing-page column — sales-led contracting, **not** self-serve checkout.

**Product shape (provisional):**
- **Price:** from $19,999 / yr (negotiated; not a fixed catalog SKU for v1 self-serve)
- **Includes (marketing):** Institutional baseline + full history on every pillar + S3 parquet drops + 300k API calls / month + dedicated account manager + DPA / redistribution / custom contracting

**Implementation shape (recommended):**
- **Do not** invent a third entitlement system. Reuse / extend the existing **`CUSTOM_*`** plan path (already used for bespoke enterprise API contracts) for access + quota.
- Commercial extras (S3 drops, DPA, dedicated AM, redistribution rights) are **ops / sales / legal** deliverables — track them, but they are outside the billing access checker.
- Optional: a public `ENTERPRISE` marker plan (or keep using private `CUSTOM_*` only) for marketing/"Contact us"; if public, it should not be purchasable via self-serve `subscribe` without a sales handoff.
- Coexistence: same one-active-SanAPI-sub rule; Enterprise replaces Institutional / packages / legacy PRO when sold.

**Deliverable:** decision recorded in §9; if a public plan row is needed, seed + admin docs; CUSTOM path verified for 300k quota + full history; non-goals list for S3/DPA.
**Depends on:** product confirmation that Enterprise = CUSTOM (or not). Does **not** block SC / SL for packages.
**Out of scope for EP code:** building an S3 delivery pipeline, contract management, or seat admin — unless product explicitly pulls them into v1.

### UI. Self-serve purchase surface
**What:** Pricing page / checkout reflecting the three-column offering (§1.1): composable package builder (left), Institutional CTA (middle), Enterprise contact CTA (right). Package checkout needs SC + SL. Institutional can use existing single-plan subscribe once **IN** lands. Enterprise is contact/sales, not cart.
**Depends on:** SC, SL for packages; IN for Institutional button; EP only for copy/CTA. ⚠️ **Confirm ownership** — if this is a frontend-team deliverable, say so explicitly in the epic rather than leaving it unassigned.

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
                      → SC (Stripe catalog — packages only)
                          → SL (subscribe/add/remove/cancel)
                              → WH (webhooks/sync)
                                  → UI (purchase surface)
                      → AM (available_metrics)    ← parallel after BA
                      → IN (Institutional fixed plan)  ← parallel to SC; standard path, not BUNDLE
                      → EP (Enterprise / CUSTOM sales path)  ← mostly product + ops; thin code
  TR, TE continuous
```

**First vertical slice that delivers value:** `BC → DP → A → PD → LC → EN → BA`. At the end of it, a bundle subscription seeded by hand grants exactly the right access and quota, the §7.6 smoke matrix is green, the BC fixture is unchanged — and not one Stripe object exists yet.

**Then:** `SC → SL → WH` for the package purchase lifecycle; **IN** in parallel for the Institutional SKU; **EP** for Enterprise sales path; `UI` for the three-column purchase surface.

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
| Data windows per package | **Full history included, no add-on in v1.** Window is global: `historical_data_in_days: nil`, `realtime_data_cut_off_in_days: 0`. Keeps `EN` free of per-grant windows. | §5.7 |
| **API calls per bundle** | **100,000/month flat, regardless of how many packages.** Explicitly *not* summed per package — "choose several bundles, you get 100k API as default". Extra call packages sold as add-ons (tiers in Notion). So `EN` computes `100_000 + sum(add_ons)` and never reads the package list for quota. | product (Dmitry) |
| Institutional API calls | **50,000/month.** Lower than a single $350 package — confirmed intentional. | product (Dmitry) |
| Institutional history | **All data, 3-year history**, while every bundle gets full history. Confirmed intentional; Institutional is therefore *not* simply the top rung on the history dimension. | product (Dmitry) |
| Institutional plan shape | **Fixed `INSTITUTIONAL` plan**, not a five-package BUNDLE (Q10). Task **IN**. | product assumption + §1.1 |
| Enterprise plan shape | **Sales-led**; reuse `CUSTOM_*` for access/quota; S3/DPA/AM are ops. Task **EP**. | §1.1 + §8 EP |
| Pricing page columns | Three offerings: packages / Institutional / Enterprise — see §1.1. | pricing mock |
| Hour / minute limits for bundles | **Constants, not derived from packages.** With a flat monthly cap there is nothing to sum. Reuse `sanapi_pro` (30k/hour, 600/minute) as burst protection — the 100k/month cap binds first, and that load is already accepted from PRO. ⚠️ Product notified, no objection needed. | §6.2 + this doc |
| Prices | **Not final, and must stay changeable.** Prices are data (catalog table + Stripe), never hardcoded in Elixir. Note: a Stripe Price is **immutable** — changing an amount means creating a new Price and archiving the old, with both alive while anyone is subscribed. Catalog needs `stripe_price_id` + an active/deprecated flag; `plans.is_deprecated` already models exactly this pattern. | product (Dmitry), §7.3 #2 |
| The "sixth package" | **It is the 500,000-call add-on, not a data pillar.** The pricing page's "six packages" = 5 data pillars + extra calls. So **PD** defines five packages, and the add-on is already modelled as `subscription_items.type: :api_calls` (§8 **LC**) — no new concept needed. | product (Dmitry) |
| Queries & signals per package | **`"all"` for every bundle** — no per-package split. They are effectively unrestricted today (12 of 13 queries and all 10 signals default to `FREE`), so enumerating them per package would *remove* access a free user already has. Needs no product input: it is the BC-preserving choice. 🔴 Must still be written explicitly — `nil` breaks every query and signal. | §6.4 |
| Existing SanAPI plans after launch | **Withdrawn from sale; current subscribers keep them indefinitely.** ✅ Mechanism already exists and is already enforced: `plans.is_deprecated` is checked in `billing_resolver.ex:27` (subscribe) and `:74` (update_subscription), so a deprecated plan can be neither newly subscribed to *nor* switched into, while existing subscriptions are untouched. ✅ It is an editable field in the plan admin (`generic_admin/plan.ex:22`) — a checkbox at launch, no deploy. This also removes the price/quota domination concern in §10. | product (Dmitry) |

**Open questions are in §15**, written for a product reader. When one is answered, move it up into the table above with its source.

Engineering-side, needing no product input: package ↔ metrics source of truth (versioned snapshot recommended — §8 **PD**), and combination cardinality (confirm sold combinations stay in the tens — §5.3).

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
- **Revenue reporting** — ✅ MRR fixed: `timeseries.ex` now sums `unit_amount × quantity` across items instead of reading item[0], and `stripe_sync.ex` no longer raises `BadMapError` on a Price-based item. **Classification is still wrong** — see §10.1 item 6.
- **Taxonomy cleanup** — remaining ~21 uncategorized metrics + Onchain → Labels moves. Now a *billing* blocker if packages read categories: an uncategorized metric is unsellable.
- **Research items** from the Market Notion page (volume vs `volume_usd`, CME, CryptoCompare liquidations, "total volume") — separate from the billing MVP.
- **No per-metric à la carte** and **no per-package call pools** in v1.

### 10.1 Abuse surfaces found on the stage run (2026-08-06)

Found by driving the real mutations against Stripe sandbox on stage, subscription 1635 /
`sub_1U1NVRCA0hGU8IEV9SFApbPq`. Items 1 to 3 are fixed; the rest need attention.

**1. ✅ Fixed — interval switch credited items that were scheduled for removal.**
`swap_stripe_items/4` sent the repriced items and the `deleted: true` entries in **one**
`update_subscription` call, and Stripe applies one `proration_behavior` per call — so the
deletions were prorated and credited. That turned keep-until-period-end (§9, Q7) into
refund-on-removal in two mutations: buy market + social monthly, `removeBundleItem("social")`,
then `switchBundleInterval`. Reproduced on stage: invoice `DD0DA60A-0185` came to $2,450.30 =
$3,500 yearly market − ~$349.85 unused monthly market − **~$699.75 unused monthly social**,
where the social credit was not owed. Scaled across five packages it is a near-full refund
after a day of using everything. Now two calls: deletions with `proration_behavior: "none"`
(the same reasoning `ItemExpiry` already applied), then the re-price with `create_prorations`.
Deletions go first so a failing re-price leaves fewer items rather than an unearned credit,
and `resource_missing` is tolerated on the deletion — without that, a re-price that failed
once made every later switch attempt die on the deletion until `remove_at` came around, a
year away on the annual interval.

**2. ✅ Fixed — access denial told a bundle customer to downgrade.** A customer paying
$1,050/month asking for `dev_activity` got *"Please upgrade to SANAPI FREE subscription"*:
`build_access_error_message/5` had a `CUSTOM_` clause but no bundle one, so bundles fell
through to the ordinal-ladder branch and `AccessChecker.min_plan/2` answered `free`. Now a
`"BUNDLE" <> _` clause names the package to buy, resolved from the latest snapshot via
`PackageSnapshot.packages_containing/1`.

**3. ✅ Fixed — a declined card cancelled the customer's paid legacy plan, and a retry then
bought a second bundle.** The worst of the three, and both halves come from one root cause:
`create_stripe_bundle_sub/3` passed no `payment_behavior`, so under Stripe's default
`allow_incomplete` a refused first invoice still answers **`{:ok, subscription}` with status
`incomplete`** — not an error tuple. The caller cannot tell a sale from a refusal.

Reproduced end to end on a second stage account:

| Time | Event |
| --- | --- |
| 13:11 | BUSINESS_PRO bought, `$420.00` **succeeded** |
| 13:14 | bundle attempted with `pm_card_chargeCustomerFail`, `$1,050.00` **failed**, subscription created `incomplete`, invoice `OLFLOTT0-0002` left **open** |
| 13:14 | **BUSINESS_PRO cancelled** — `subscribe/2` had read the incomplete subscription as bought |
| 13:16 | good card attached, bundle bought again — **allowed**, because `classify_active_sanapi/1` does not count `incomplete` as active |
| 13:16 | `$630.02` succeeded = `$1,050 − $419.98`, the cancelled BUSINESS_PRO's unused time funding the retry |

That left the customer with no access at all between 13:14 and 13:16 despite having paid, and
then with **two Stripe bundle subscriptions** — one active, one incomplete still holding an open
$1,050 invoice that Stripe retries for ~23 hours. With a working card now on file, a successful
retry would have made it active too: two active bundles, billed twice.

Two fixes. The root one is `payment_behavior: "error_if_incomplete"`, so Stripe creates nothing
and returns an error — no incomplete subscription, no open invoice, nothing to duplicate, and
the failure is visible to `subscribe/2`. Nothing is lost by refusing: `off_session: true` means
no authentication is on offer, so a card needing 3DS fails either way, and supporting that is
`default_incomplete` plus a client confirmation step — a feature, not a fallback. The second fix
is defence in depth: `cancel_replaceable_if_live/2` only cancels the legacy plan when the new
row is in `@active_statuses`, the same predicate `stale_replaced_subscriptions/0` applies, so
the inline cancel and its hourly retry now agree on what counts as replaced. The legacy path had
this guard all along (`subscription.ex:319`); the bundle path had lost it.

**4. A scheduled removal cannot be undone.** No mutation clears `remove_at`, and
`addBundleItem` on the same SKU hits the `(subscription_id, sku)` unique index. A misclick
costs the customer a month. Needs an un-remove path — clearing `remove_at`, no Stripe call.

**5. No cooldown on `switchBundleInterval`.** Nothing rate-limits it. A loop generates
unbounded Stripe invoices and proration line items, burns our Stripe API quota, and makes the
invoice history unreadable. Worth a guard (reject if the interval changed within the last N
hours) before public launch.

**6. Refund-after-credit double-dip — ops, not code.** Flipping intervals leaves a large
Stripe **credit balance**; $9,449.96 was observed on stage. Refunding the cash invoice without
netting the credit hands the customer both. Finance/support rule needed: never refund an
invoice on a subscription holding a non-zero credit balance without netting it off first.

**7. Bundle subscriptions fall out of the SanAPI reporting count (§7.5 C5).**
`Timeseries.product_name/1` maps only two hardcoded Stripe product ids to
`"SanAPI by Santiment"` / `"Sanbase by Santiment"`, but `Catalog.ensure_stripe_product/2`
creates **one Stripe Product per bundle SKU**, so a bundle item's `price.product` is an
unknown `prod_…` and the raw id is returned. `stats/1` counts `san_api_active_and_paid` via
`product_name_starts_with("SanAPI")`, so bundles are not counted, and
`plan_nickname`/`product_name` name only one of a bundle's packages. MRR itself is now correct.
Fixing the classification needs a decision on how a bundle maps to a reporting product; the
expanded price carries `metadata["sanbase_sku"]` as a detection hook. Current behaviour is
pinned by a test in `test/sanbase/billing/subscription/timeseries_test.exs` so the gap stays
visible.

**8. `past_due` grants full access — dunning is ~3 weeks of free bundle access.**
`subscription/query.ex:8` grants access on `:active` **and** `:past_due`. Pre-existing for
every plan, but the exposure scales with price: ~3 weeks of $1,050/month access instead of
$70. Belongs to task **TR**, still not started.

**9. Interval flipping leaves credit balances that silently cover future invoices.** The stage
subscription's 2027 renewal already shows `Applied balance -$3,500.00`, amount due $0.00.
Product decision needed: is interval switching free, once per period, or renewal-only?

**Not an abuse surface, but found in the same run:** the `/admin/bundle_subscriptions` "make a
real GraphQL call" card posts to `SanbaseWeb.Endpoint.url()`, i.e. the admin pod's own
endpoint. `:graphql_cache` is only started when `container_type() in ["web", "all"]`
(`application.ex:355-363`), so `cachex_key_lock.ex:58` hard-matches `{:ok, cache_record}`
against `{:error, :no_cache}` and every cached query 500s there. Use the card's curl command
against the API host, or make the target host an input on the card.

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

## 13. Progress and next concrete step

### 13.0 Done so far

| Task | State | What landed |
|------|-------|-------------|
| **BC** — characterization fixture | ✅ done | `test/fixtures/billing/access_matrix.json` + CI-asserted test. Byte-identical through every change since. |
| **DP** — `Plan.type/1` dispatch seam | ✅ done | ~20 sites dispatch on plan type; `plan_type_dispatch_test.exs` is the checklist. |
| **PD** — package definition + snapshot | ✅ done | `Bundle.Package` (five packages as category rules), `bundle_package_snapshots` table, `Bundle.PackageSnapshot` with `publish/1` and `pending_changes/0`, dual-membership leak check. Admin diff *screen* not built — `pending_changes/0` is the logic it needs. |
| **LC** — local multi-item model | ✅ done | `subscription_items`, `bundle_prices` catalog, `BUNDLE` marker plan rows (301 month / 302 year, SanAPI). |
| **EN** — entitlement resolver | ✅ done | `Bundle.Resolver.resolve/2` (pure) + `sync/1` (persists). All §6.3 rules applied. |
| **BA** — bundle access path | ✅ done | Access, data windows, call quota, and `get_available_metrics_for_plan` all implemented. `bundle_entry_points/0` is empty. The four Sanbase-side limits answer as PRO (§5.9). |
| **OB** — admin visibility | ✅ done | Two admin pages, `/admin/bundle_packages` and `/admin/bundle_subscriptions`. |
| **WH** — webhook / multi-item sync | ✅ done | `Bundle.ItemSync` + branches in `stripe_event.ex` for `created` / `updated` / `deleted`. Bundle detected by price id in `bundle_prices`; adopts a dashboard-created bundle; reconciles items and re-resolves; drops the quota on cancel. Legacy single-item path byte-identical. The `api_call_limits` write (§5.10) was already in place. |
| **AM** — available metrics | ✅ done | `getAvailableMetrics(plan: BUNDLE, metricPackages: [...])` catalogs from the latest published snapshot. AccessChecker entitlement path clears the last BA raise. Non-bundle plans unchanged. |
| **SC** — Stripe catalog | ✅ done | `Bundle.Catalog` via `Billing.sync_bundle_catalog_with_stripe/0` (also in `@reboot` `sync_products_with_stripe`). 12 local rows; package Stripe Prices via Price API; `api_calls_500k` amount still TBD. |
| **SL** — subscribe lifecycle | ✅ done | `Bundle.Lifecycle` + GraphQL mutations; SaleControls activate/deactivate; legacy auto-replace; `upgrade_downgrade` guard. |
| **UI** | ⬜ not started | Three-column pricing / checkout (webapp). |
| **IN** — Institutional | ⬜ not started | Fixed flagship plan (§1.1 middle column). Specced in §8 **IN**; not a BUNDLE. |
| **EP** — Enterprise | ⬜ not started | Sales-led custom tier (§1.1 right column). Specced in §8 **EP**; prefer CUSTOM path. |

**Admin pages.** `/admin/bundle_packages` shows what each package contains live vs
published, the pending-changes diff, and publishes snapshots.
`/admin/bundle_subscriptions` creates, edits and cancels bundle subscriptions
(**no Stripe object** — local test rows only), shows the resolved entitlement, and
has three testers: *Decide* (calls the access checker directly, both products,
side by side with a standard plan), *Scenarios* (generated from the packages the
subscription actually owns, each row carrying its own expectation), and *Request*
(POSTs to the real `/graphql` with an API key, so it exercises the full plug
pipeline).

**Automatic end-to-end test.** `test/sanbase_web/graphql/billing/bundle_api_access_test.exs`
makes real authenticated requests as a bundle subscriber. It is the only test that
proves a live request carries the entitlement from context to access checker, and
it found the `Graphql.Complexity` site the inventory missed (§5.9).

✅ **A live bundle request is served to a real customer.** Access, data windows and
the call quota all resolve from the entitlement, and `bundle_api_access_test.exs`
proves it with a non-exempt email — the test that used to assert a raise now asserts
the response, plus one that the reported allowance is the flat base rather than
PRO's, and one that a purchased add-on raises it.

⚠️ **`@santiment.net` users are exempt from quota** (`user_has_limits?/1` in
`api_call_limit.ex`). That no longer hides a raise, but it still means testing with
your own Santiment key proves access without exercising the quota numbers at all.
The `Request` tester on the admin page inherits this exactly. The integration test
states it in a test of its own rather than leaving the suite looking like it covered
both.

**Category names confirmed.** `Bundle.Package` names its categories `"Market"`,
`"Development"`, `"Social"`, `"On-chain"`, `"On-chain Labels"`, and all five resolve
against real data on stage. One thing to look at before publishing a snapshot in a
new environment: `development` came back with only three metrics (`dev_activity`,
`dev_activity_1d`, `dev_activity_contributors_count`), which is thin for a sellable
package. `PackageSnapshot.materialize/0` still refuses to build and lists the
categories that *do* exist if a name is ever wrong.

**What a bundle can do now:** be bought (staff preview in `:legacy` mode, or public after Go Live) via `subscribeBundle`, with add/remove/switch/cancel. Catalog browsing still works via `getAvailableMetrics(plan: BUNDLE, metricPackages: [...])` without a subscription.

✅ **Stripe-initiated changes now land locally.** **WH** closed the last gap that
needed a human: a bundle changed in the Stripe dashboard, or an item change whose
`subscription.updated` events arrive after the mutation returned, is reconciled
against `subscription_items` and re-resolved. A bundle assembled entirely in the
dashboard is adopted onto the `BUNDLE` marker plan for its interval.

**Outside WH's scope:** §7.3 #4 (`stripe_sync.ex`) and #5 (`timeseries.ex`) are
first-item *read* assumptions — a bundle's plan in the reconciliation job and its
MRR attribution. They do not crash and they are not on the access path. **WH**
covers only the webhook write path; those two are tracked on their own.

### 13.1 Next

1. **`IN`** — Institutional as a fixed standard plan. Does not share the multi-item path; uses offering gate + standard `subscribe`.
2. **`EP`** — confirm Enterprise = CUSTOM sales path; thin plan/admin work only.
3. **`UI`** — three-column pricing / checkout once SL (packages) and IN (flagship CTA) exist; use `bundleCatalog` + plan flags (`is_private` / `is_deprecated`).
4. When product prices `api_calls_500k`: set amounts + `Sanbase.Billing.sync_bundle_catalog_with_stripe()` (or wait for `@reboot`) — no code change.
5. Use `/admin/bundle_offering` to activate bundle plans and/or deactivate Business Pro/Max when ready.

Prices on the mock are **not final** and must not gate further work.

### 13.2 Original plan, for reference

Three things, in this order. The first two are pure infrastructure and can start immediately — they need no product decisions at all.

1. **Task BC** — the characterization fixture (~a day). Pure upside: required by the DoD, never needs rewriting, and it makes every later review a diff instead of an argument.
2. **Task DP** — `Plan.type/1` + the §7.6 smoke matrix (~1–2 days). Land it as a behavior-preserving refactor with the fixture green. Its first commit should be the smoke matrix *failing* for `BUNDLE` on all eight Group A rows — that failure list is the epic's real definition of scope.
3. **First working slice** (~a day, after DP) — narrow but complete, from the database row all the way to the answer a request gets. One two-package entitlement written by hand into `subscriptions.bundle_entitlement`, `Bundle.Access` implemented for `plan_has_access?` and `api_call_limits` only, and the bundle branch filled in at just those two sites. Prove that a seeded bundle subscription gets exactly the right access and quota while the BC fixture stays unchanged. That validates the §5 design end to end before any Stripe, package-definition, or UI work. Everything it produces is kept — none of it is throwaway.

✅ **All four of the items that were flagged as causing rework are now answered** — data windows (uniform full history, §5.7), queries/signals (`"all"`, §6.4), the hour/minute rule (constants, §9), and the base quota (flat 100k, §9). Task **A** is no longer on the critical path; what remains of it is in §15 and none of it blocks development.

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

## 15. Questions for product

**How to use this section.** Every time the build needs a product decision, it gets appended here — short question, why we need it, an example where that helps. No code, no jargon. When it's answered, the answer moves into the §9 table and the question is struck from here.

Ordered by what is blocking work right now.

### Blocking now

**Q4. Are there extra API-call tiers beyond the 500,000 one, and what do they cost?**

Q1 established that the "sixth package" is the 500,000-call add-on. If Notion has other tiers, we need to know they exist — the prices themselves can come later.

**Prices are not needed to start building.** They are only needed for the Stripe catalog and the purchase page, which come last. What we need now is the *list of things sold*, not their amounts.

*Answer:* partially — 500,000 confirmed; is that the only tier?

The 500,000 tier is built and working. Adding another tier later is one line of code — this only matters for knowing what to put in the price list.

---

~~**Q5. What does a package customer see in Sanbase, the web app?**~~ ✅ **Answered:** the same as a SanAPI PRO customer with no Sanbase subscription. Implemented as `Bundle.equivalent_standard_plan/0` — see §5.9.

---

### Needed before launch

~~**Q14. Does the web app hide plans marked `isPrivate`?**~~ ✅ **Answered by reading the frontend, no product call needed.** It does not — it never asks for the field.

The pricing page uses `queryProductsWithPlans` from `san-webkit-next` (pinned at `lib-e24c3dd8-180526`), whose query selects `id name interval amount isDeprecated`. `isPrivate` appears nowhere in `san-webkit` or in `sanbase-app`. Filtering is `!plan.isDeprecated` plus a name allow-list: `{FREE, PRO, MAX}` for Sanbase, `{BUSINESS_PRO, BUSINESS_MAX, CUSTOM}` for SanAPI.

Three consequences, all now built in:

* **`is_deprecated` is the only sale switch.** `SaleControls` moves that and nothing else; writing `is_private` would change production data with no observable effect.
* **`is_private` must never become a purchase gate.** On production `FREE` on both products and Sanbase `PRO`, `PRO_PLUS` and `MAX` are all `is_private = true` *and sold on the pricing page every day*. The column's comment — "plans that customers can't subscribe on their own" — has never been enforced anywhere, and enforcing it would stop those sales.
* **`BUNDLE` rows can never appear on the pricing page by flipping any flag.** They are excluded server-side by name and would be dropped client-side by the allow-list anyway. Making the offering visible is frontend work against `bundleCatalog` — a launch dependency, not a configuration change.

Left over, and cosmetic: a bundle subscriber's account page renders the literal `"BUNDLE"`, because `getPlanName` falls back to the raw name for anything outside its display map. Worth a webkit entry before launch.

---

**Q6. Does Institutional's "3 seats" ship in the first version?**

We have no concept of seats today — one subscription belongs to one account. Adding seats is a separate piece of work from packages. If it has to be there at launch, it needs planning now rather than later.

*Answer:* pending

---

~~**Q7. What happens if a customer removes a package in the middle of a month?**~~ ✅ **Answered:** adding takes effect immediately, removing takes effect at the end of the paid period, and nothing is refunded — the customer keeps the package for the time they bought. Built: the deadline is recorded on the item and an hourly job carries it out. See §5.11.

---

**Q8. Do package subscriptions get the 14-day free trial?**

Existing plans have one. If packages get it too, we need to know whether the trial covers any combination the customer picks, or only a specific one.

*Answer:* pending

---

**Q9. What happens when a customer's payment fails?**

Today the subscription is marked "past due" and we keep serving them for a while. For packages: do we cut off all access, or drop them to something smaller until they pay?

*Answer:* pending

---

**Q13. What do we offer an existing API customer who wants to change their plan?**

Once the old plans are withdrawn from sale, a customer on SanAPI PRO can stay on it forever — but the moment they want to change anything, their only options are the new packages. PRO gives them 600,000 calls for $420/month. The closest package costs $350 for 100,000, or $1,050 with the 500,000 add-on.

So a customer who is happy today will find that changing their plan costs more and gives less. We should decide what we tell them before the first one asks.

*Example:* a PRO customer wants to add Social. Today they would move to a package plus the add-on and go from 600,000 calls to 600,000 — at a higher price.

Not blocking any code. It needs an answer before launch, not before development.

*Answer:* pending

---

### Confirmations (we have assumed an answer — tell us if it is wrong)

**Q10. Institutional is a single fixed plan, not something assembled from packages.**

We read $799/month as one fixed product: everything included, 3-year history, 50,000 calls. We are building it that way (task **IN**), which is simpler and cheaper than treating it as a combination of packages. Say so if it is meant to be composable.

*Assumed answer:* fixed plan. Captured in §1.1 and §8 **IN**.

---

**Q11. Yearly Institutional looks like it is missing its discount.**

Yearly packages give roughly two months free — $350/month becomes $3,500/year. Yearly Institutional is $9,500 against $9,588 for twelve monthly payments, which is about 1%. We think this is a typo on the pricing page rather than a decision. Provisional either way — amounts stay in catalog data.

*Assumed answer:* typo.

---

**Q12. Prices can still change, and we are building for that.**

Prices will live as data rather than in code, so they can be added, replaced and retired without a developer. One constraint worth knowing: a price in Stripe cannot be edited. Changing an amount means creating a new price and retiring the old one, and both then exist side by side — anyone already subscribed keeps what they signed up for. That is normal and fine; it just means "change the price" is really "add the new one, stop selling the old one".

*Assumed answer:* prices not final; build for change.

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
