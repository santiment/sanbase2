# Scope: metric grouping for the five API data packages

**Status:** T1–T3 done — the taxonomy is written and applicable; T4–T7 open
**Date:** 2026-08-10
**Branch:** `group-metrics`
**Companion docs:**
- `docs/composable-api-plans-handover.md` — billing side of the same epic
- `docs/metric-taxonomy-open-questions.md` — the metrics product still has to place

**What exists now:**

| Artefact | Path |
|---|---|
| Taxonomy for all five packages **and** the importer, in one self-contained file | `lib/sanbase/metric/category/taxonomy_importer.ex` |
| Tests | `test/sanbase/metric/category/taxonomy_importer_test.exs` |

One file on purpose: stage and production have no `mix`, and the file can be
loaded into a running node (`kubectl cp` + `Code.require_file/1`, or pasted into
`bin/sanbase remote`) and exercised before it is deployed anywhere. The five
taxonomies are `@taxonomy_*` module attributes.

Group names follow the database's existing convention - **Title Case** (`Network
Activity`, `Social Dominance`, `Top Holders`), which predates this work. The
Notion pages mix sentence case and Title Case; where they disagree with the
database, the database wins, and a test enforces it.

```elixir
Sanbase.Metric.Category.TaxonomyImporter.plan()             # dry run, writes nothing
Sanbase.Metric.Category.TaxonomyImporter.apply!(["market"]) # write, one package at a time
```

**Applied to stage and production on 2026-08-10.** Production took 1090 new
mapping rows, 825 ungrouped rows deleted, 27 groups dissolved, 2 renamed, 70
groups in place, and reported **zero unknown metric names** - every name in the
taxonomy resolves against production. A second `plan/0` is all zeros, so the
importer is idempotent against real data and not only against fixtures.

107 production mappings remain ungrouped, and every one of them is an open
question: 104 labeled-entity flow and balance metrics (Q1), `ethSpentOverTime`
(Q5), `social_active_users` and `nft_social_volume` (Q2, Q3).

Source product pages (Notion):

- [Market data plan](https://app.notion.com/p/santiment/Market-data-plan-3912a82d136180d4a99cd1ad45c9122e)
- [Development data package](https://app.notion.com/p/santiment/Development-data-package-37d2a82d136180bda65df9debcd27503)
- [Social data plan](https://app.notion.com/p/santiment/Social-data-plan-37d2a82d136180cf8711e9a0e1f8419c)
- [Onchain core plan](https://app.notion.com/p/santiment/Onchain-core-plan-3842a82d13618064814bf990b6ba1ddb)
- Onchain Labels (final list)

---

## 1. What already exists, and therefore is not in this scope

Reading the code first changes the shape of the task considerably. Three of the
four things the task asks for are already built.

| Task line | State | Evidence |
|---|---|---|
| "Create category Market / Social Sentiment / Onchain(Core) / Onchain Labels / Development" | **Done** — all five categories exist | `metric_categories`; Market was merged out of `Financial` + `Derivatives` + `Indicators` in `priv/repo/migrations/20260804140000_merge_market_metric_categories.exs` |
| Category → group → metric data model, including a metric in two groups | **Done** | `metric_categories` → `metric_groups` → `metric_category_mappings`; the unique index is on `(metric_registry_id, category_id, group_id)` with `nulls_distinct: false` (`20251027154645_...exs`), so several rows per metric are legal and intended |
| Admin UI to create groups and assign metrics | **Done** | `/admin/metric_registry/categorization`, LiveViews under `lib/sanbase_web/live/metric_registry/categorization_live/` |
| Category/group filters on the internal Available Metrics screen | **Done** | `Sanbase.AvailableMetrics.apply_filters/2` (`available_metrics.ex:177-211`), `AvailableMetricsLive` |
| "Create a Market data / Development / Social / Onchain Core / Onchain Labels plan in Stripe" | **Done** | `Sanbase.Billing.Plan.Bundle.Catalog` — 12 `bundle_prices` rows (5 packages + `api_calls_500k`, month + year), synced to Stripe by `Billing.sync_bundle_catalog_with_stripe/0`. Purchase, add/remove item, webhooks, entitlements, quota and admin visibility are all done (tasks PD, LC, EN, BA, SC, SL, WH, AM, OB in the handover doc) |
| Package → category rule | **Done** | `Bundle.Package`: `market → "Market"`, `development → "Development"`, `social → "Social"`, `onchain_core → "On-chain"`, `onchain_labels → "On-chain Labels"` |

**Do not rename the category rows to the Notion titles.** `Bundle.Package.category`
is a database key; the Notion names ("Social Sentiment", "Onchain(Core)") are the
marketing names and already live in `Bundle.Package.name`. A rename silently
empties a package — `PackageSnapshot.materialize/0` refuses to build when a named
category is missing, which is the guard, but the rename is still pointless churn.

So the remaining work is: **the groups, the metric→group assignments, the
cross-category moves, and a public API surface that can filter on them.**

---

## 2. What is actually missing

### 2.1 Groups do not exist for Market at all

The merge migration deliberately created no groups: *"Groups are deliberately not
created. The Notion taxonomy for Market … is separate work"* — every Market
mapping came over with `group_id = NULL`. All nine to eleven Market groups
(Pricing, Marketcap, Volume, ETF, Indicators, NFT, Funding rates, Open Interest,
Deprecated, and possibly CEX Liquidations) are greenfield.

For the other four categories the group state is unknown from the code alone and
must be read from production — see §5, queries Q1–Q3.

### 2.2 Group count from the Notion pages

| Package | Category row | Groups asked for | Notes |
|---|---|---|---|
| Market data | `Market` | 9 (+1 future: CEX Liquidations) | ~85 metric rows on the page; `nft_market_volume` moves out to On-chain Labels |
| Development data | `Development` | 4 | smallest, and a good first slice |
| Social Sentiment | `Social` | 26 | heavy dual membership (see §2.3) |
| Onchain Core | `On-chain` | 15 | heavy dual membership; a "Move to onchain labels" column |
| Onchain Labels | `On-chain Labels` | 11 | receives the moved metrics |

Roughly **65 groups** and, at ~1046 registry rows, on the order of **1200–1400
mapping rows** once dual membership is counted.

### 2.3 Dual membership is a second row, not a second column

The Social and Onchain Core pages ask for metrics to sit in a narrow group *and*
in a roll-up group at the same time:

- Positive / Negative / Balance / Weighted Sentiment → also **Regular Sentiment**
- Bullish / Neutral / Bearish → also **Bullish/Bearish/Neutral Sentiment**
- Positive / Neutral / Negative docs count → also **Labeled social Volume**
- Positive / Neutral / Negative ratio → also **Sentiment Ratio**
- Address activity / Circulation and dormancy / Transaction and payment /
  Contract-related → also **Network Activity**
- MVRV and valuation / Coin age and dormant supply / Network profit-loss and
  supply → also **Network value**

The schema supports this: one mapping row per `(metric, category, group)`. Two
consequences that must be handled by the apply script, not discovered later:

1. **The ungrouped row must be deleted when grouped rows are added.** A metric
   with both a `group_id = NULL` row and a grouped row shows up twice in
   `getOrderedMetricsV2` and once under "Ungrouped" in the admin filter.
2. **`display_order` is per mapping row**, so a dual-membership metric needs an
   order in each group. `MetricGroup.changeset` requires `display_order` on the
   group too.

### 2.4 A "move" is a delete plus an insert

"Move `nft_market_volume` to Onchain Labels" and the "Move to onchain labels"
rows are *moves*, not dual membership: the row in the source category must be
deleted. Left in place, the metric stays sellable through the source package —
`PackageSnapshot` unions per category, so a Market-only customer would keep
getting an On-chain Labels metric. This is exactly the leak the handover doc
flags in task PD.

### 2.5 The public API cannot filter by category or group

`getAvailableMetrics` takes `product`, `plan`, `hasIncompleteData`,
`metricPackages`, `nameRegexFilter` — and nothing else
(`lib/sanbase_web/graphql/schema/queries/metric_queries.ex:23-45`). The filtering
that exists is in `Sanbase.AvailableMetrics` and is keyed on **numeric ids**,
which differ per environment and are useless in a public API. New work:

- add `category` / `group` **name** arguments (or a small filter input object)
- return the taxonomy alongside the names, otherwise a client cannot build a
  category picker; today the field is `list_of(:string)`
- exclude `Deprecated` and `Internal Metrics` groups by default

### 2.6 Deprecated / Internal exclusion is not implemented where it matters

`PackageSnapshot` excludes registry rows flagged `is_deprecated` or `is_hidden`
(`package_snapshot.ex:280-281`) — it does **not** know about a group *named*
"Deprecated" or "Internal Metrics". Every metric the Notion pages park in a
Deprecated group but which is not flagged in the registry (all twenty
BitMEX/FTX/BNB rows on the Market page, for instance) is currently **sold** as
part of the package. Two fixes, both needed:

1. Flag those registry rows `is_deprecated` — the correct fix, and it also fixes
   documentation, the metric list and alerts.
2. Add a group-name exclusion to `PackageSnapshot.build_contents/1` as a belt —
   because "which group is it in" is the thing product edits, and it will drift
   from the registry flag again.

---

## 3. Work breakdown

Ordered so that nothing later needs earlier work redone. Estimates are
engineering days, excluding the taxonomy data entry itself where noted.

### T0 — Production inventory (0.5d)

Run the §5 queries against production, commit the results as CSV under
`priv/repo/taxonomy_inventory/`. Everything below is sized off these numbers, and Q6
and Q9 will find real problems before any write happens.

### T1 — Taxonomy as checked-in data (1d + data entry) — done

One `@taxonomy_*` attribute per package in
`lib/sanbase/metric/category/taxonomy_importer.ex`:

```elixir
%{
  category: "Market",
  groups: [
    %{name: "Pricing", display_order: 1, metrics: ["price_usd", "price_btc", ...]},
    %{name: "Volume", display_order: 3, metrics: [...]},
    ...
  ]
}
```

Why a file and not the admin UI: 65 groups and ~1300 assignments done by hand in
a LiveView are unreviewable, unrepeatable across stage and production, and
impossible to diff when product changes their mind. A file gets a code review, a
dry run, and one command per environment.

**The data entry is product's transcription, not engineering's.** The Notion
tables are the source of truth and list metric names directly. Engineering
supplies the file format and the validator; whoever owns the taxonomy fills it.
Budget ~1 day of transcription for Social, ~1 day for Onchain Core, a few hours
for each of the rest.

Template metrics need a decision in the format: the pages list
`price_usd_change_{{interval}}`, which is **one** registry row with
`is_template = true`, not N metrics. Assign the template row; `PackageSnapshot`
already expands it via `Registry.resolve_safe/1`.

### T2 — Validator (0.5d)

A mix task that reads the spec files and reports, without writing anything:

- names in the spec that match no `metric_registry` row and no code metric
- registry rows in the category that the spec does not place in any group
- metrics named in two groups where the spec did not mark it as intentional
- metrics named in two *categories* (the leak check from §2.4)
- duplicate group names within a category (the unique index would reject them)

This is what makes T1 safe to hand to a non-engineer. Run it in CI over the
committed spec.

### T3 — Importer, idempotent (1d) — done

`Sanbase.Metric.Category.TaxonomyImporter`, informed by the existing
`scripts/move_metrics_to_category.exs` and
`scripts/move_onchain_metrics_to_onchain_labels_category.exs`:

- upsert groups via `Category.create_group_if_not_exists/1`
- upsert mappings via `Category.create_mapping_if_not_exists/1`
- **delete the `group_id = NULL` mapping** for any metric that got a grouped row
- assign `display_order` densely within each group
- `--dry-run` prints the diff; a second run is a no-op

Not a migration: the taxonomy will be re-applied many times as product iterates,
and a migration runs once.

### T4 — Cross-category moves (0.5d)

The "Move to onchain labels" rows and `nft_market_volume`. Same script, an
explicit `moves:` section, so that the delete of the source-category row is
recorded and reviewable rather than implied.

### T5 — Deprecated / Internal handling (1d)

- set `is_deprecated` on the registry rows the pages park in Deprecated groups
- group-name exclusion in `PackageSnapshot.build_contents/1`, with a test that a
  metric in a `Deprecated` group is absent from every package
- the same exclusion in the public `getAvailableMetrics` default

### T6 — Public `getAvailableMetrics` filtering (2d)

- `category` and `group` name arguments
- a taxonomy-carrying response shape, additive so the existing
  `list_of(:string)` contract is untouched (a new field or a new query — decide
  in review; breaking the existing field is not acceptable, it is a public API)
- names resolved to ids server-side, unknown names an error rather than an empty
  list
- Deprecated / Internal hidden by default, with an explicit opt-in flag
- cache key must include the new arguments (`cache_resolve` ttl 300)

### T7 — Re-publish the package snapshot and verify (0.5d)

`PackageSnapshot.pending_changes/0` → review the diff → publish. Then verify per
package that the metric set matches the Notion page, and that
`getAvailableMetrics(plan: BUNDLE, metricPackages: [...])` returns it. Existing
bundle subscriptions are pinned to the old snapshot version, so check what the
change does to anyone already subscribed on stage.

### T8 — Documentation follow-ups (not engineering)

The "What need to add" column of every Notion page is documentation work on
academy pages (missing metrics, OHLC is daily-only, exchange lists, ETF list).
Tracked separately; it does not block any of the above.

**Total engineering: ~7 days**, plus ~2–3 days of taxonomy transcription owned by
product, plus T9/T10 below if they are pulled into this epic.

### T9 — CEX liquidations via CryptoCompare (research, then ~5–8d if approved)

Not a grouping task — it is a new data pipeline. The shape is known because
`funding_rate` and `open_interest` already work exactly this way:

- CryptoCompare futures liquidations endpoint → new
  `lib/sanbase/cryptocompare/liquidations/` with a historical scheduler, a
  worker, a point struct and a pause/resume worker, mirroring
  `lib/sanbase/cryptocompare/open_interest/`
- Kafka topic + ClickHouse table (`Backfill` `@allowed_tables` gains a third
  entry)
- registry rows for `total_liquidations`, `exchange_liquidations`,
  `total_per_settlement_currency` (the three names on the Notion page)
- a `CEX Liquidations` group in Market

Research output first: does the subscribed CryptoCompare plan include the
liquidations endpoint, at what granularity, for which exchanges, and how far
back. That answer decides whether this is 5 days or a vendor conversation.

### T10 — Volume metric questions (research, 1–2d)

Product questions from the Market page, answerable from ClickHouse and the
scrapers rather than by product:

| Question | What we know now |
|---|---|
| `daily_trading_volume_usd` vs `volume_usd` | Answered on the Notion page: `daily_trading_volume_usd` is scraped from CMC and covers the exchanges CMC tracks; `volume_usd` is our own trading volume. Needs writing into the academy page, not researching |
| What is `volume_dominance` doing? | **No hit anywhere in the repo** — it is not a registry-backed or code metric in `sanbase`. Either it never shipped or it lives entirely upstream. Check `metric_registry` on production (Q9) before answering product |
| Volume per exchange? | Feasibility question for the data team — we hold per-exchange volume for the exchange-labelled on-chain metrics, but not obviously for trading volume |
| Volume for CME? | Depends on the CryptoCompare instrument coverage; same research as T9 |
| A `total_volume` = ETF + CME + CEX + DEX metric | Technically a derived metric over four sources with different intervals and different asset coverage. Answerable only after the CME and per-exchange answers. Treat as a design task, not a grouping task |
| Purpose of `funding_rate`? | It is the raw CryptoCompare per-instrument funding rate table (`Cryptocompare.Backfill` `@allowed_tables`), which the three `funding_rates_aggregated_*` metrics aggregate. Whether it should stay exposed as a public metric is a product call |

---

## 4. Risks

| Risk | Mitigation |
|---|---|
| Grouping changes what a package contains, and packages are sold | T7 reviews `pending_changes/0` before publishing; existing subscriptions stay pinned to their snapshot version |
| A metric ends up in two categories and leaks across packages | T2 validator check, run in CI |
| Category rename empties a package | Do not rename (§1); `materialize/0` refuses to build on a missing category |
| Deprecated metrics sold because the registry flag was never set | T5, both halves |
| Taxonomy applied to stage but not production, or vice versa | Spec file in the repo plus an idempotent script; never hand edits in the admin UI for bulk changes |
| `display_order` collisions after the Market merge | The merge migration left three interleaved sequences; T3 renumbers densely per group, which resolves it as a side effect |

---

## 5. SQL to run on production

Read-only. Q6 and Q9 are the two that are likely to surface real problems.

### Q1 — Categories, with how much sits in each

```sql
SELECT c.id,
       c.name,
       c.display_order,
       count(DISTINCT g.id)  AS groups,
       count(DISTINCT m.id)  AS mappings
FROM metric_categories c
LEFT JOIN metric_groups g ON g.category_id = c.id
LEFT JOIN metric_category_mappings m ON m.category_id = c.id
GROUP BY c.id, c.name, c.display_order
ORDER BY c.display_order NULLS LAST, c.name;
```

### Q2 — Every group that exists today, per category

```sql
SELECT c.name AS category,
       g.id,
       g.name AS group_name,
       g.display_order,
       count(m.id) AS mappings
FROM metric_groups g
JOIN metric_categories c ON c.id = g.category_id
LEFT JOIN metric_category_mappings m ON m.group_id = g.id
GROUP BY c.name, g.id, g.name, g.display_order
ORDER BY c.name, g.display_order NULLS LAST, g.name;
```

### Q3 — How many metrics are still ungrouped, per category

```sql
SELECT c.name AS category,
       count(*) FILTER (WHERE m.group_id IS NULL)     AS ungrouped,
       count(*) FILTER (WHERE m.group_id IS NOT NULL) AS grouped
FROM metric_category_mappings m
JOIN metric_categories c ON c.id = m.category_id
GROUP BY c.name
ORDER BY c.name;
```

### Q4 — The full current assignment, as a CSV to diff against the Notion pages

One row per mapping, so a dual-membership metric appears twice. This is the file
the taxonomy spec is written against.

```sql
SELECT c.name                                   AS category,
       coalesce(g.name, '(ungrouped)')          AS group_name,
       coalesce(r.metric, m.metric)             AS metric,
       CASE WHEN m.metric_registry_id IS NULL THEN 'code' ELSE 'registry' END AS source,
       r.is_template,
       r.is_hidden,
       r.is_deprecated,
       r.status,
       m.display_order
FROM metric_category_mappings m
JOIN metric_categories c ON c.id = m.category_id
LEFT JOIN metric_groups g ON g.id = m.group_id
LEFT JOIN metric_registry r ON r.id = m.metric_registry_id
ORDER BY c.name, g.display_order NULLS LAST, g.name, m.display_order NULLS LAST, metric;
```

### Q5 — Registry metrics with no category at all

The handover doc says 21 were left uncategorized; this is the current number.

```sql
SELECT r.id, r.metric, r.is_template, r.is_hidden, r.is_deprecated, r.status
FROM metric_registry r
LEFT JOIN metric_category_mappings m ON m.metric_registry_id = r.id
WHERE m.id IS NULL
ORDER BY r.metric;
```

### Q6 — Rows the apply script has to clean up

**(a) A metric that is both grouped and ungrouped in the same category.** These
are the duplicate rows of §2.3 and they exist wherever grouping was applied
partially.

```sql
SELECT c.name AS category,
       coalesce(r.metric, m.metric) AS metric,
       count(*) FILTER (WHERE m.group_id IS NULL)     AS ungrouped_rows,
       count(*) FILTER (WHERE m.group_id IS NOT NULL) AS grouped_rows
FROM metric_category_mappings m
JOIN metric_categories c ON c.id = m.category_id
LEFT JOIN metric_registry r ON r.id = m.metric_registry_id
GROUP BY c.name, coalesce(r.metric, m.metric)
HAVING count(*) FILTER (WHERE m.group_id IS NULL) > 0
   AND count(*) FILTER (WHERE m.group_id IS NOT NULL) > 0
ORDER BY c.name, metric;
```

**(b) A metric in more than one category — the package leak check.**

```sql
SELECT coalesce(r.metric, m.metric) AS metric,
       count(DISTINCT m.category_id) AS categories,
       string_agg(DISTINCT c.name, ', ' ORDER BY c.name) AS category_names
FROM metric_category_mappings m
JOIN metric_categories c ON c.id = m.category_id
LEFT JOIN metric_registry r ON r.id = m.metric_registry_id
GROUP BY coalesce(r.metric, m.metric)
HAVING count(DISTINCT m.category_id) > 1
ORDER BY categories DESC, metric;
```

### Q7 — Code metrics vs registry metrics per category

Code metrics (`metric_registry_id IS NULL`) carry no deprecation flags, so
`PackageSnapshot` sells every one of them. Worth knowing how many there are.

```sql
SELECT c.name AS category,
       count(*) FILTER (WHERE m.metric_registry_id IS NULL)     AS code_metrics,
       count(*) FILTER (WHERE m.metric_registry_id IS NOT NULL) AS registry_metrics
FROM metric_category_mappings m
JOIN metric_categories c ON c.id = m.category_id
GROUP BY c.name
ORDER BY c.name;
```

### Q8 — Deprecated and hidden metrics sitting in a sold category

These are already excluded from packages by `sellable?/1`, so the list is the
gap between "what the Notion page shows" and "what a customer gets". Expect the
counts to differ from the Deprecated groups on the pages — that difference is
what T5 fixes.

```sql
SELECT c.name AS category,
       coalesce(g.name, '(ungrouped)') AS group_name,
       r.metric,
       r.is_deprecated,
       r.is_hidden,
       r.status,
       r.hard_deprecate_after
FROM metric_category_mappings m
JOIN metric_categories c ON c.id = m.category_id
JOIN metric_registry r ON r.id = m.metric_registry_id
LEFT JOIN metric_groups g ON g.id = m.group_id
WHERE r.is_deprecated OR r.is_hidden
ORDER BY c.name, group_name, r.metric;
```

### Q9 — Do the Notion metric names exist?

Run this per package with the page's metric list pasted into the `VALUES`. Any
row that comes back `NULL, NULL` is a name the taxonomy cannot be applied to —
a typo, a renamed metric, or one that was never built. It is the single most
useful query here, and it answers the `volume_dominance` question directly.

```sql
WITH wanted(metric) AS (
  VALUES
    ('price_usd'), ('price_btc'), ('price_eth'), ('price_usdt'),
    ('price_usd_5m'), ('price_histogram'), ('price_usd_change_1h'),
    ('daily_closing_price_usd'), ('daily_high_price_usd'),
    ('daily_low_price_usd'), ('daily_opening_price_usd'),
    ('daily_avg_price_usd'),
    ('rank'), ('marketcap_usd'), ('fully_diluted_valuation_usd'),
    ('daily_avg_marketcap_usd'), ('daily_closing_marketcap_usd'),
    ('total_market_marketcap_usd'), ('total_market_2_marketcap_usd'),
    ('total_market_3_marketcap_usd'),
    ('volume_usd'), ('volume_usd_5m'), ('daily_trading_volume_usd'),
    ('volume_dominance'),
    ('etf_volume_usd_5m'), ('daily_etf_flow'), ('total_etf_flow'),
    ('btc_s_and_p_price_divergence'), ('rsi_4h'), ('rsi_1d'), ('rsi_7d'),
    ('price_daa_divergence'), ('adjusted_price_daa_divergence'),
    ('money_supply'),
    ('nft_market_volume'),
    ('funding_rate'), ('funding_rates_aggregated_by_exchange'),
    ('funding_rates_aggregated_by_settlement_currency'),
    ('total_funding_rates_aggregated_per_asset'),
    ('exchange_open_interest'), ('open_interest_per_settlement_currency'),
    ('total_open_interest'),
    ('total_liquidations'), ('exchange_liquidations'),
    ('total_per_settlement_currency')
)
SELECT w.metric               AS wanted,
       r.id                   AS registry_id,
       r.metric               AS registry_metric,
       r.is_template,
       r.is_deprecated,
       r.is_hidden,
       r.status,
       c.name                 AS current_category,
       coalesce(g.name, '(ungrouped)') AS current_group
FROM wanted w
LEFT JOIN metric_registry r ON r.metric = w.metric
LEFT JOIN metric_category_mappings m ON m.metric_registry_id = r.id
LEFT JOIN metric_categories c ON c.id = m.category_id
LEFT JOIN metric_groups g ON g.id = m.group_id
ORDER BY (r.id IS NULL) DESC, w.metric;
```

Template metrics will not match by exact name — `price_usd_change_{{interval}}`
is stored with the braces, so paste it verbatim rather than expanded. To see all
templates in one place:

```sql
SELECT r.metric, r.parameters, c.name AS category, coalesce(g.name, '(ungrouped)') AS group_name
FROM metric_registry r
LEFT JOIN metric_category_mappings m ON m.metric_registry_id = r.id
LEFT JOIN metric_categories c ON c.id = m.category_id
LEFT JOIN metric_groups g ON g.id = m.group_id
WHERE r.is_template
ORDER BY c.name NULLS FIRST, r.metric;
```

### Q10 — Published package snapshot, if one exists

Confirms what customers are currently entitled to, before anything is changed.

```sql
SELECT s.id,
       s.version,
       s.published_at,
       jsonb_object_agg(k, jsonb_array_length(s.contents -> k)) AS metrics_per_package
FROM bundle_package_snapshots s,
     LATERAL jsonb_object_keys(s.contents) AS k
GROUP BY s.id, s.version, s.published_at
ORDER BY s.version DESC
LIMIT 5;
```

And which subscriptions are pinned to which version — the set that T7 can affect:

```sql
SELECT sub.bundle_entitlement ->> 'package_snapshot_version' AS snapshot_version,
       sub.status,
       count(*) AS subscriptions
FROM subscriptions sub
WHERE sub.bundle_entitlement IS NOT NULL
GROUP BY 1, 2
ORDER BY 1, 2;
```

---

## 6. Suggested order of execution

1. **T0** — run §5 on production, commit the CSVs. Nothing is sized until this is done.
2. **T1 on Development only** — 4 groups, smallest page. Prove the spec format end to end.
3. **T2, T3** — validator and apply script, exercised against Development.
4. **T1 for Market** — the greenfield case, and the one with the deprecated-metric problem.
5. **T5** — Deprecated / Internal handling, while Market is fresh.
6. **T1 for Social, Onchain Core, Onchain Labels** + **T4** moves.
7. **T6** — public API filtering.
8. **T7** — re-publish the snapshot, verify per package.
9. **T9 / T10** — research tracks, in parallel throughout; they gate no other item.
