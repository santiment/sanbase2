# Non-Crypto Assets Support Plan

Support for non-crypto assets (gold, silver, stocks, indices like S&P 500 — e.g. the
non-crypto instruments tradeable on Hyperliquid) as first-class entities with their own
database table, GraphQL API and price data flow.

## Why a new table

The `project` table carries heavy crypto-specific baggage: `coinmarketcap_id`,
`main_contract_address`, `token_address`, `token_decimals`, `total_supply`,
`infrastructure` FK, `eth_addresses`, `contract_addresses`, `icos`, ecosystem mappings.
None of it applies to gold or TSLA. A separate `non_crypto_assets` table keeps both
models clean.

## Design decisions (proposed)

| Decision | Choice | Rationale |
|---|---|---|
| Table name | `non_crypto_assets` | Plural, descriptive, no clash with `project` |
| Schema module | `Sanbase.NonCryptoAsset` | Mirrors `Sanbase.Project` conventions |
| Asset categorization | `asset_type` string column (Ecto.Enum: `stock`, `commodity`, `index`, `forex`, `fund`, `other`) | Simple, queryable, extensible without join table |
| External source mapping | Extend `source_slug_mappings` with nullable `non_crypto_asset_id` FK + check constraint | One source of truth for source→slug mappings; Hyperliquid scraper already reads this table |
| GraphQL API | `allNonCryptoAssets` / `nonCryptoAssetBySlug` | Mirrors `allProjects` / `projectBySlug` naming users already know |
| Slug uniqueness | Unique within `non_crypto_assets` + validation against `project` slugs | Slugs are the universal identifier in metric/price APIs; collisions with crypto slugs would be ambiguous |
| Metric system integration | Phase 2 (optional) | `Sanbase.Metric.available_slugs/2` guard intersects with project slugs (`lib/sanbase/metric/metric.ex:618`) — needs deliberate changes, not a quick win |

## Scope

Goal of the first iteration is **availability/discoverability only**: the assets exist
in Postgres, are listable/fetchable via GraphQL, and their prices flow through the
existing Hyperliquid pipeline. Explicitly out of scope (future work, when there is
demand):

- **Watchlists** — non-crypto assets cannot be added to watchlists.
- **Screeners / `ListSelector`** — no integration with the screener filter/order
  machinery; the new list query has no selector.
- **`getMetric` integration** — kept as the deferred Phase 4.
- Anything else that mirrors `Project.List` complexity (pagination, min_volume,
  ordering options) — the asset list is tens of rows.

---

## Phase 1 — Database

### Step 1.1: Migration — create `non_crypto_assets`

New file: `priv/repo/migrations/<timestamp>_create_non_crypto_assets.exs`

```elixir
defmodule Sanbase.Repo.Migrations.CreateNonCryptoAssets do
  use Ecto.Migration

  def change() do
    create table(:non_crypto_assets) do
      add(:slug, :string, null: false)
      add(:name, :string, null: false)
      add(:ticker, :string)
      add(:asset_type, :string, null: false)
      add(:description, :text)
      add(:logo_url, :string)
      add(:website_link, :string)
      add(:is_hidden, :boolean, default: false, null: false)
      add(:hidden_since, :utc_datetime)
      add(:hidden_reason, :text)
      add(:metadata, :jsonb, default: "{}")

      timestamps()
    end

    create(unique_index(:non_crypto_assets, [:slug]))
    create(index(:non_crypto_assets, [:asset_type]))
  end
end
```

Notes:
- `metadata` jsonb for source-specific extras (e.g. Hyperliquid index composition,
  stock exchange, ISIN) without schema churn.
- `is_hidden`/`hidden_since`/`hidden_reason` mirror the `project` visibility pattern
  so list queries can filter the same way.

### Step 1.2: Migration — extend `source_slug_mappings`

New file: `priv/repo/migrations/<timestamp>_add_non_crypto_asset_to_source_slug_mappings.exs`

- Add `non_crypto_asset_id` (nullable, `references(:non_crypto_assets, on_delete: :delete_all)`).
- Make `project_id` nullable (currently non-null).
- Add check constraint: exactly one of `project_id` / `non_crypto_asset_id` set:

```elixir
create(
  constraint(:source_slug_mappings, :exactly_one_asset_reference,
    check: "(project_id IS NULL) <> (non_crypto_asset_id IS NULL)"
  )
)
```

This lets a Hyperliquid mapping row (`source = "hyperliquid"`, `slug = "GOLD"`) point at
a non-crypto asset the same way crypto coins point at projects. The BBO websocket
scraper (`lib/sanbase/hyperliquid/bbo/bbo_websocket_scraper.ex`) discovers coins from
this table and reconciles every 60s — non-crypto assets join the subscription list with
no scraper code changes beyond the query update in Step 3.1.

Alternative considered: a separate `non_crypto_asset_source_mappings` table. Rejected —
every consumer of source mappings (scraper subscription list, slug resolution in
`bbo_prices.ex`) would need to query and union two tables.

### Step 1.3: Ecto schema + context

New files:
- `lib/sanbase/non_crypto_asset/non_crypto_asset.ex` — schema + changeset + queries
- (optional) keep CRUD in same module, following `Sanbase.Project` style

```elixir
defmodule Sanbase.NonCryptoAsset do
  use Ecto.Schema

  schema "non_crypto_assets" do
    field(:slug, :string)
    field(:name, :string)
    field(:ticker, :string)
    field(:asset_type, Ecto.Enum, values: [:stock, :commodity, :index, :forex, :fund, :other])
    field(:description, :string)
    field(:logo_url, :string)
    field(:website_link, :string)
    field(:is_hidden, :boolean, default: false)
    field(:hidden_since, :utc_datetime)
    field(:hidden_reason, :string)
    field(:metadata, :map, default: %{})

    has_many(:source_slug_mappings, Sanbase.Project.SourceSlugMapping)

    timestamps()
  end
end
```

Public API — deliberately minimal, NOT a mirror of `Sanbase.Project` / `Project.List`.
The asset count is small (tens, not thousands), so no pagination, no selector
machinery, no list-options framework:
- `by_slug/1`
- `list/1` — opts: `:asset_type`, `:include_hidden`; ordered by `name`
- `slugs/0` — all visible slugs (needed for discoverability + metric integration later)
- `changeset/2` + `create/1` — only what seeding and the admin panel need

Anything else (update/delete helpers, filtering combinators) gets added when an actual
caller appears.

Changeset validations:
- required: `slug`, `name`, `asset_type`
- `unique_constraint(:slug)`
- slug-collision check against `project` table (`Project.by_slug/1` must return nil) —
  prevents one slug meaning two assets in slug-keyed APIs.

### Step 1.4: Update `Sanbase.Project.SourceSlugMapping`

`lib/sanbase/project/source_slug_mapping.ex`:
- add `belongs_to(:non_crypto_asset, Sanbase.NonCryptoAsset)`
- relax changeset: require `source` + `slug` + exactly one of the two FKs
- helper: `list_pairs_for_source/1` returning `{external_name, sanbase_slug}` for BOTH
  projects and non-crypto assets (single query with two left joins + coalesce)

---

## Phase 2 — GraphQL API

Follows the exact pattern of project queries
(`lib/sanbase_web/graphql/schema/queries/project_queries.ex`).

### Step 2.1: Types

New file: `lib/sanbase_web/graphql/schema/types/non_crypto_asset_types.ex`

```elixir
object :non_crypto_asset do
  field(:id, non_null(:id))
  field(:slug, non_null(:string))
  field(:name, non_null(:string))
  field(:ticker, :string)
  field(:asset_type, non_null(:non_crypto_asset_type))
  field(:description, :string)
  field(:logo_url, :string)
  field(:website_link, :string)
  # price fields — Phase 3:
  # field(:price_usd, :float)        — latest price, resolver hits ClickHouse
  # field(:price_history, ...)       — or served via getMetric, see Phase 4
end

enum :non_crypto_asset_type do
  value(:stock)
  value(:commodity)
  value(:index)
  value(:forex)
  value(:fund)
  value(:other)
end
```

### Step 2.2: Queries

New file: `lib/sanbase_web/graphql/schema/queries/non_crypto_asset_queries.ex`

```elixir
object :non_crypto_asset_queries do
  @desc "Fetch all non-crypto assets (stocks, commodities, indices, ...)"
  field :all_non_crypto_assets, list_of(:non_crypto_asset) do
    meta(access: :free)
    arg(:asset_type, :non_crypto_asset_type)

    cache_resolve(&NonCryptoAssetResolver.all_non_crypto_assets/3)
  end

  @desc "Fetch a non-crypto asset by its slug"
  field :non_crypto_asset_by_slug, :non_crypto_asset do
    meta(access: :free)
    arg(:slug, non_null(:string))

    cache_resolve(&NonCryptoAssetResolver.non_crypto_asset_by_slug/3)
  end
end
```

Notes:
- `cache_resolve` gives 300s TTL + jitter, same as `projectBySlug`.
- No `ProjectPermissions` middleware needed — that middleware exists only to block
  expensive per-project fields on list queries; nothing expensive here yet.
- No pagination, no `selector` input object — the full list is tens of rows; an
  optional `asset_type` filter is all the filtering needed for now.

### Step 2.3: Resolver

New file: `lib/sanbase_web/graphql/resolvers/non_crypto_asset_resolver.ex`

- `all_non_crypto_assets/3` → `Sanbase.NonCryptoAsset.list/1`
- `non_crypto_asset_by_slug/3` → `Sanbase.NonCryptoAsset.by_slug/1`, error tuple on nil
  (mirror `project_resolver.ex:39` style: `{:error, "Non-crypto asset with slug ... not found"}`)

### Step 2.4: Mount in main schema

`lib/sanbase_web/graphql/schema.ex`:
- `import_types(Graphql.Schema.NonCryptoAssetQueries)` (~line 91–139 block)
- `import_types(Graphql.NonCryptoAssetTypes)`
- `import_fields(:non_crypto_asset_queries)` inside `query do` block

---

## Phase 3 — Price data

The Hyperliquid BBO pipeline in this branch already does: websocket → Kafka
(`hyperliquid_bbo_prices` topic) → ClickHouse (`hyperliquid_bbo_prices` table), with
coins discovered from `source_slug_mappings`.

### Step 3.1: Subscribe scraper to non-crypto coins

- Update the subscription-list query used by
  `lib/sanbase/hyperliquid/bbo/bbo_websocket_scraper.ex` to use the new
  `list_pairs_for_source/1` (Step 1.4) so it returns both project-mapped and
  non-crypto-asset-mapped coins. Scraper reconciliation loop picks them up automatically.
- Same change in slug resolution inside `lib/sanbase/hyperliquid/bbo/bbo_prices.ex`.

### Step 3.2: Seed data

- Extend/clone `scripts/seed_hyperliquid_source_slug_mappings.exs` into
  `scripts/seed_non_crypto_assets.exs`:
  - insert `non_crypto_assets` rows (gold, silver, S&P 500, individual stocks, ...)
  - insert `source_slug_mappings` rows (`source = "hyperliquid"`,
    `slug = <hyperliquid coin name>`, `non_crypto_asset_id = ...`)
- Asset list source: Hyperliquid meta API — classify which markets are non-crypto
  (manual curation, it is a short list).

### Step 3.3: Price read API

Two options, pick based on where prices land:

**Option A (recommended start): reuse the BBO table.** Non-crypto prices arrive
through the same BBO websocket channel into `hyperliquid_bbo_prices`. The existing
`HyperliquidBbo` GraphQL queries already serve timeseries by slug — they work for
non-crypto slugs as soon as Steps 3.1–3.2 land. Optionally add a `priceUsd` field on
`:non_crypto_asset` resolving to latest mid-price ((bid+ask)/2) from
`Sanbase.Hyperliquid.BboPrices`.

**Option B (if a dedicated price feed is added later): dedicated ClickHouse table**
(e.g. `non_crypto_asset_prices`, mirroring `asset_prices_v3` minus `price_btc`/
`marketcap_usd`) + read module mirroring `lib/sanbase/prices/price.ex` +
`price_sql_query.ex`. More work, only justified when prices come from a non-BBO source
(OHLCV feed, external stock API).

---

## Phase 4 (optional, later) — `getMetric` integration

Expose non-crypto prices through `getMetric(metric: "price_usd")` so existing tooling
(charts, alerts, screeners) works on them. Non-trivial because:

1. **Adapter**: new `Sanbase.NonCryptoAsset.MetricAdapter` implementing
   `Sanbase.Metric.Behaviour`, registered in `Sanbase.Metric.Helper` `@modules` list
   (`lib/sanbase/metric/helper.ex:23-34`). Module order matters there — registration
   must not shadow `Sanbase.Price.MetricAdapter` for crypto slugs (dispatch would need
   slug-aware selection, like how `Price` overrides `PricePair`).
2. **Slug guard**: `Sanbase.Metric.available_slugs/2`
   (`lib/sanbase/metric/metric.ex:610-630`) intersects adapter slugs with
   `Project.List.projects_slugs()` — must union with `NonCryptoAsset.slugs/0`.
3. **Selector resolution**: anywhere a slug is resolved to a project
   (`Project.by_slug/1` in metric paths) needs a fallback to non-crypto assets.
4. **Metric metadata — `availableNonCryptoAssets`**: add to the `:metric_metadata`
   object (`lib/sanbase_web/graphql/schema/types/metric_types.ex:344`), mirroring the
   existing `available_slugs` (line 399) / `available_projects` (line 407) pair:

   ```elixir
   @desc ~s"""
   List of non-crypto assets (stocks, commodities, indices, ...) whose slug can be
   provided to the `timeseriesDataJson` (and co.) field to fetch the metric.
   """
   field :available_non_crypto_assets, list_of(:non_crypto_asset) do
     cache_resolve(&MetricResolver.get_available_non_crypto_assets/3, ttl: 300)
   end
   ```

   Resolver (`MetricResolver.get_available_non_crypto_assets/3`) mirrors
   `get_available_projects/3`: take the metric's available slugs, intersect with
   `NonCryptoAsset.slugs/0`, map to structs. Depends on item 2 above — the slug guard
   in `Metric.available_slugs/2` currently drops anything that is not a project slug,
   so this field returns `[]` until the guard unions in non-crypto slugs (or the
   resolver reads adapter slugs pre-guard). `availableSlugs` should then also include
   non-crypto slugs so the two fields stay consistent.

Defer until the dedicated GraphQL API proves insufficient. Keep as separate PR.

---

## Phase 5 — Admin & housekeeping

### Step 5.1: Admin panel

New file: `lib/sanbase_web/generic_admin/non_crypto_asset.ex` following
`SanbaseWeb.GenericAdmin.Project` (`lib/sanbase_web/generic_admin/project.ex`):
`:new` + `:edit` actions, fields: slug, name, ticker, asset_type, description,
logo_url, website_link, hidden flags. Register in the generic admin resource list.

### Step 5.2: Tests

- `test/sanbase/non_crypto_asset_test.exs` — changeset validations (slug uniqueness,
  collision with project slug, required fields), `list/1` filtering/pagination.
- `test/sanbase_web/graphql/non_crypto_asset_api_test.exs` — `allNonCryptoAssets`
  (`assetType` filter, hidden exclusion), `nonCryptoAssetBySlug` (found/not-found).
- Factory entry in `test/support/factory.ex` (`:non_crypto_asset`).
- `source_slug_mappings` check-constraint test (row with both/neither FK fails).

### Step 5.3: ClickHouse / Kafka infra (outside this repo)

If Option B in Step 3.3 is chosen: ClickHouse table DDL + Kafka topic + consumer config
live in the infra/ETL repos — coordinate separately.

---

## Execution order

| # | Item | Depends on |
|---|---|---|
| 1 | Migrations (1.1, 1.2) | — |
| 2 | `Sanbase.NonCryptoAsset` schema + context (1.3) | 1 |
| 3 | `SourceSlugMapping` update (1.4) | 1, 2 |
| 4 | GraphQL types/queries/resolver/mount (2.1–2.4) | 2 |
| 5 | Scraper + bbo_prices query updates (3.1) | 3 |
| 6 | Seed script + run (3.2) | 2, 3 |
| 7 | Latest-price field on type (3.3 Option A) | 4, 5 |
| 8 | Admin panel (5.1) | 2 |
| 9 | Tests (5.2) | alongside each step |
| 10 | `getMetric` integration (Phase 4) | separate PR, later |

Steps 1–4 are pure Postgres/GraphQL work, shippable and testable without any price
data. Steps 5–7 light up prices via the existing Hyperliquid pipeline.

## Open questions

1. **Slug convention** — `gold`, `silver`, `sp500` vs prefixed (`nc-gold`)? Unprefixed
   reads better in APIs; the project-slug collision check (Step 1.3) makes it safe.
   Proposal: unprefixed.
2. **Is BBO mid-price good enough as "the price"** for these assets, or is a proper
   OHLCV/close feed needed (→ Option B in 3.3)?
3. **Should `allProjects` ever include non-crypto assets** (e.g. via a flag)? Proposal:
   no — keep the APIs separate, frontends merge if needed.
4. **Hyperliquid coin naming** for non-crypto markets (their meta API naming for
   stock/index perps) — verify exact `coin` strings before seeding mappings.
