# Metric taxonomy: open questions

**Date:** 2026-08-10
**Owner of the answers:** product - engineering cannot decide these from the code.
**Applies to:** the `@taxonomy_*` attributes in
`lib/sanbase/metric/category/taxonomy_importer.ex`, applied by
`Sanbase.Metric.Category.TaxonomyImporter.apply!/1`.

Everything in this file is a metric that is currently **ungrouped in production**
and that the Notion tables do not place in any group, or place inconsistently.
None of it blocks applying the taxonomy for the metrics that *are* decided - the
apply script simply leaves these rows ungrouped until an answer arrives.

Ordered by how much is at stake.

---

## Q1. The 103 labeled-entity flow and balance metrics - sellable group, or Deprecated?

**Category:** On-chain Labels. **Blocking:** yes, for that package only.

These appear on **no group** of the Onchain Labels(final list) page. They are one
coherent family: a matrix of flows and balances between labeled entity types
(`cexes`, `dexes`, `dex_traders`, `defi`, `traders`, `whale`, `other`, `genesis`,
`labeled`, `unlabeled`, `proxy`).

The page does have a bare sub-header **"DeFi labeled-entity flows"** inside its
Deprecated block with nothing under it, which reads like this family was being
triaged and the triage was never finished.

**Why it matters:** 103 metrics is ~21% of the On-chain Labels package. If they
are left out, a customer who buys On-chain Labels does not get them. If they are
put in Deprecated, they are excluded from the package for good.

**Engineering recommendation:** create one sellable group, **Labeled entity
flows**, and move individual metrics to Deprecated later if product wants.
Deprecating a fifth of a package by omission is the more expensive mistake, and
it is far cheaper to demote a metric later than to explain a gap to a customer.

**What we need:** either "yes, one group called X", or a split of the list below.

### Flow metrics (78)

- `cexes_to_defi_flow`
- `cexes_to_defi_flow_change_{{interval}}`
- `cexes_to_dex_flow`
- `cexes_to_dex_flow_change_{{interval}}`
- `cexes_to_dex_traders_flow`
- `cexes_to_dex_traders_flow_change_{{interval}}`
- `cexes_to_other_flow`
- `cexes_to_other_flow_change_{{interval}}`
- `cexes_to_traders_flow`
- `cexes_to_whale_flow`
- `cexes_to_whale_flow_change_{{interval}}`
- `defi_to_cexes_flow`
- `defi_to_cexes_flow_change_{{interval}}`
- `defi_to_dex_traders_flow`
- `defi_to_dex_traders_flow_change_{{interval}}`
- `defi_to_dexes_flow`
- `defi_to_dexes_flow_change_{{interval}}`
- `defi_to_other_flow`
- `defi_to_other_flow_change_{{interval}}`
- `defi_to_traders_flow`
- `defi_to_whale_flow`
- `defi_to_whale_flow_change_{{interval}}`
- `dex_to_cexes_flow`
- `dex_to_cexes_flow_change_{{interval}}`
- `dex_traders_to_cexes_flow`
- `dex_traders_to_cexes_flow_change_{{interval}}`
- `dex_traders_to_defi_flow`
- `dex_traders_to_defi_flow_change_{{interval}}`
- `dex_traders_to_dexes_flow`
- `dex_traders_to_dexes_flow_change_{{interval}}`
- `dex_traders_to_other_flow`
- `dex_traders_to_other_flow_change_{{interval}}`
- `dex_traders_to_whale_flow`
- `dex_traders_to_whale_flow_change_{{interval}}`
- `dexes_to_defi_flow`
- `dexes_to_defi_flow_change_{{interval}}`
- `dexes_to_dex_traders_flow`
- `dexes_to_dex_traders_flow_change_{{interval}}`
- `dexes_to_other_flow`
- `dexes_to_other_flow_change_{{interval}}`
- `dexes_to_traders_flow`
- `dexes_to_whale_flow`
- `dexes_to_whale_flow_change_{{interval}}`
- `labeled_to_labeled_flow`
- `labeled_to_unlabeled_flow`
- `other_to_cexes_flow`
- `other_to_cexes_flow_change_{{interval}}`
- `other_to_defi_flow`
- `other_to_defi_flow_change_{{interval}}`
- `other_to_dex_traders_flow`
- `other_to_dex_traders_flow_change_{{interval}}`
- `other_to_dexes_flow`
- `other_to_dexes_flow_change_{{interval}}`
- `other_to_traders_flow`
- `other_to_traders_flow_change_{{interval}}`
- `other_to_whale_flow`
- `other_to_whale_flow_change_{{interval}}`
- `traders_to_cexes_flow`
- `traders_to_defi_flow`
- `traders_to_dexes_flow`
- `traders_to_other_flow`
- `traders_to_other_flow_change_{{interval}}`
- `traders_to_whale_flow`
- `traders_to_whale_flow_change_{{interval}}`
- `unlabeled_to_labeled_flow`
- `unlabeled_to_unlabeled_flow`
- `whale_to_cexes_flow`
- `whale_to_cexes_flow_change_{{interval}}`
- `whale_to_defi_flow`
- `whale_to_defi_flow_change_{{interval}}`
- `whale_to_dex_traders_flow`
- `whale_to_dex_traders_flow_change_{{interval}}`
- `whale_to_dexes_flow`
- `whale_to_dexes_flow_change_{{interval}}`
- `whale_to_other_flow`
- `whale_to_other_flow_change_{{interval}}`
- `whale_to_traders_flow`
- `whale_to_traders_flow_change_{{interval}}`

### Balance metrics (25)

- `all_known_balance`
- `defi_balance`
- `defi_cex_balance`
- `defi_dex_balance`
- `dex_cex_balance`
- `dex_traders_cex_balance`
- `dex_traders_defi_balance`
- `dex_traders_dex_balance`
- `dex_traders_whale_balance`
- `genesis_balance`
- `other_cex_balance`
- `other_defi_balance`
- `other_dex_balance`
- `other_dex_traders_balance`
- `other_traders_balance`
- `proxy_balance`
- `trader_balance`
- `traders_cex_balance`
- `traders_defi_balance`
- `traders_dex_balance`
- `traders_whale_balance`
- `unlabeled_balance`
- `whale_cex_balance`
- `whale_defi_balance`
- `whale_dex_balance`

---

## Q2. `social_active_users` - which group?

**Category:** Social. Not on the Social data plan page at all. It is a code
metric (served by an adapter module, not the registry). Social Volume? Community
Message count? Internal?

---

## Q3. `nft_social_volume` - Social Volume?

**Category:** Social. It *is* on the page, but in the block after the
struck-through Deprecated rows that has no group header of its own. Filed
nowhere by the spec until confirmed.

---

## Q4. The 40 Farcaster / Discord / Professional-Traders-Chat rows

**Category:** Social. **We made an assumption here - please confirm or correct.**

On the page these sit in the same unheaded block as `nft_social_volume`, after
the Deprecated rows, and they are **not** struck through. We filed each one into
the group its name implies - `sentiment_positive_farcaster` into Positive
Sentiment, `social_dominance_discord` into Social dominance, and so on - rather
than into Deprecated.

If those sources are being retired, say so and they move to Deprecated as a
block.

---

## Q5. `ethSpentOverTime` - which group, or drop it?

**Category:** On-chain. A legacy camelCase code metric, absent from the Onchain
core plan page. Everything else in that category is placed.

---

## Q6. `topHoldersPercentOfTotalSupply` - which group, or drop it?

**Category:** On-chain Labels. Same shape as Q5: legacy camelCase code metric,
absent from the page. The other three `amount_in_*_top_holders` metrics are
placed in **Top Holders**, which is the group it is already in.

No longer blocks anything: the taxonomy now uses the database's existing
`Top Holders` group rather than a differently-cased one, so the group is reused
instead of dissolved and this metric simply stays where it is. Still worth an
answer, but it is a cleanup now.

---

## Q7. Two metrics on the page that do not exist — **answered, no action**

**Category:** On-chain Labels, group **Labeled Balances**.

- `inflow_per_label_and_owner`
- `outflow_per_label_and_owner`

They are **aliases**, not metrics of their own:
`lib/sanbase/clickhouse/metric/metric_files/label_based_metric_metrics.json`
lists them as the aliases of `exchange_inflow_per_exchange` and
`exchange_outflow_per_exchange`. Both canonical names are on the same page under
Centralized Exchanges / Labeled exchange, and the spec places them there. The
page lists one family twice under two names; nothing is missing.

Labeled Balances therefore ships with `balance_per_owner` and
`balance_per_label_and_owner_delta`, which is complete.

---

## Q8. 26 metrics the Notion pages deprecate but the registry does not flag

**Not a grouping question** - grouping them as "Deprecated" does **not** stop
them being sold. `Bundle.PackageSnapshot` excludes a metric from a package by
reading `metric_registry.is_deprecated` / `is_hidden`, not by looking at the
group name. All 26 below are currently **inside a sold package**.

Two things are needed, and the second one is not optional:

1. Group them as Deprecated - the spec files already do this.
2. Set `is_deprecated` on the registry rows. Until that happens they stay
   sellable, and they also stay in the docs and in alerts.

**Market (20)** - the whole BitMEX / FTX / BNB block:
`bitmex_perpetual_basis`, `bitmex_perpetual_basis_ratio`, `bitmex_perpetual_price`,
`bitmex_composite_price_index`, `bitmex_perpetual_open_interest`,
`bitmex_perpetual_open_value`, `bitmex_perpetual_funding_rate`,
`bitmex_perpetual_funding_rate_change_{{interval}}`, `usdt_bnb_open_value`,
`usdt_bnb_open_interest`, `usdt_bnb_funding_rates`, `busd_bnb_open_value`,
`busd_bnb_open_interest`, `busd_bnb_funding_rates`, `ftx_perpetual_open_interest`,
`ftx_perpetual_funding_rate`, `dydx_perpetual_funding_rate`,
`deribit_perpetual_funding_rate`, `bitfinex_perpetual_funding_rate`,
`huobi_perpetual_funding_rate`

**Social (6)** - struck through on the page, live in the registry:
`social_dominance_twitter_news`, `social_dominance_twitter_news_1h_moving_average`,
`social_dominance_twitter_news_24h_moving_average`, `sentiment_balance_twitter_news`,
`sentiment_negative_twitter_news`, `social_volume_twitter_news`

Also worth a look while you are there: `sentiment_positive_twitter_news` *is*
flagged, while `sentiment_negative_twitter_news` is not. The Twitter-news family
is half-deprecated in the registry.

---

## Q9. Two On-chain groups with no Notion equivalent

**Category:** On-chain. Both hold real metrics, and both names are absent from the
Onchain core plan page. The spec dissolves them into the page's groups:

| Old group | Metric | Spec puts it in |
|---|---|---|
| `Long-term holders` | `dormant_circulation_{{timebound}}` | Circulation and dormancy |
| `Long-term holders` | `spent_coins_age_band_{{low}}_to_{{high}}` | Coin age and dormant supply |
| `Defi` | `new_deployed_contracts` | Contract-related |

Confirm, or keep `Long-term holders` as its own group.

---

## Q13. Two Market metrics in the category but on no Notion page

**Category:** Market. Found after the stage apply: 41 mappings, 39 placed by the
spec, 2 left ungrouped and named nowhere on the Market data plan page. Run this to
see which:

```sql
SELECT coalesce(r.metric, m.metric) AS metric,
       CASE WHEN m.metric_registry_id IS NULL THEN 'code' ELSE 'registry' END AS source
FROM metric_category_mappings m
JOIN metric_categories c ON c.id = m.category_id
LEFT JOIN metric_registry r ON r.id = m.metric_registry_id
WHERE c.name = 'Market' AND m.group_id IS NULL
ORDER BY 1;
```

They are harmless where they are - ungrouped, still in the Market package - but
they belong in a group like everything else. The importer now reports this class
of metric as **unplaced**, so the equivalent on production will be visible before
the apply rather than after.

---

## Q11 and Q12. `morpho_supply_apy` and the eight Euler metrics - **answered**

**Answered 2026-08-11.** All nine go to **On-chain Labels / Lending and Borrowing
Protocols**, and the `Euler` and `Morpho` groups are dissolved from On-chain.

- `euler_borrow_apy`, `euler_supply_apy`, `euler_total_protocol_borrowed_usd`,
  `euler_total_protocol_supplied_usd`, `euler_vaults_borrow_apy`,
  `euler_vaults_supply_apy`, `euler_vaults_total_borrowed_usd`,
  `euler_vaults_total_supplied_usd`
- `morpho_supply_apy`

They were on neither Notion page and sat in protocol-specific On-chain groups
that are leftovers of the v1 taxonomy; the other thirteen `euler_*` and twenty-one
`morpho_*` metrics are already in that group. Product's answer was "if there is
no better place" - so if one of these turns out to belong somewhere else, it is a
one-line spec change, not a decision that has to be made again.

Implemented as `moves` in `@taxonomy_onchain` plus the names in the On-chain
Labels group, with `Euler` and `Morpho` in `delete_groups`. A move is a delete
plus an insert, so nothing stays sellable through the On-chain package.

---

## Q14. Three `crvusd_savings_*` names the page spells with a trailing `crv`

**Category:** On-chain Labels, group **Yield, Savings & Staking**. Low stakes.

The Onchain Labels page cells read `crvusd_savings_total_suppliedcrv`,
`crvusd_savings_distributionscrv` and `crvusd_savings_apycrv`. The spec uses the
names without the trailing `crv`, which is what the neighbouring `sky_savings_*`
and `gho_savings_*` rows look like, so this reads as a paste artifact in Notion.

Nothing is at risk either way: a name with no mapping row is reported as unknown
and skipped, so a wrong guess writes nothing and shows up in `plan()`.

---

## Q15. Three metrics the spec places that no page names

Real metrics, in the category, closest group chosen by name. Confirm or move:

| Metric | Spec puts it in | Page has |
|---|---|---|
| `liquity_action_new_debt_usd` | On-chain Labels / Lending and Borrowing Protocols | `liquity_action_new_debt` only |
| `average_transfer_5m` | On-chain / Transaction and Payment | `median_transfer_5m` only |
| `miners_balance` | On-chain / Miners | `miners_total_supply`, `avg_difficulty` |

Two more where the page and the metric name disagree, and the spec follows the
name: `sentiment_neutral_youtube_videos` is listed under *Neutral ratio* but is
not a `_ratio_` metric, so it is in **Neutral Sentiment**;
`neutral_docs_count_telegram` is listed under *Positive docs count* and is in
**Neutral Docs Count**.

---

## Q10. Deferred research questions from the Market page

Not taxonomy - recorded here so they are not lost. Details in
`docs/metric-taxonomy-grouping-scope.md` (T9, T10).

- **Volume per exchange** - feasible? Data-team question.
- **Volume for CME** - depends on CryptoCompare instrument coverage.
- **A `total_volume` metric = ETF + CME + CEX + DEX** - a derived metric over
  four sources with different intervals and asset coverage. Design task; blocked
  on the two answers above.
- **CEX liquidations via CryptoCompare** (`total_liquidations`,
  `exchange_liquidations`, `total_per_settlement_currency`) - a new pipeline
  mirroring `lib/sanbase/cryptocompare/open_interest/`. First question is whether
  our CryptoCompare plan includes the liquidations endpoint, at what granularity,
  for which exchanges, and how far back.
- **Is `funding_rate` meant to be public?** It is the raw CryptoCompare
  per-instrument funding-rate table that the three `funding_rates_aggregated_*`
  metrics aggregate. It is grouped under Funding rates for now.

---

## Environment note, not a question

Stage and production have diverged in **both** directions, so an unknown-metric
list is environment-specific and is not evidence of a bad spec:

- Production has metrics stage lacks - Market 76 mappings vs 41, Development 15
  vs 3, and `fluid_total_protocol_supplied_usd` in On-chain Labels.
- Stage has metrics production lacks - `morpho_supply_apy` and the eight
  `euler_*` metrics of Q11 and Q12 did not appear in production's ungrouped list,
  so on production those moves are a no-op.

Compare an unknown list against that environment's own ungrouped rows before
treating an entry as a spec error.

---

## Answered while writing this

- **`volume_dominance`** - exists as a registry metric (no adapter module, hence
  no hit when grepping `sanbase`). Placed in Market / Volume.
- **`integral_sentiment_bb_1d`** - exists; it was already in the old
  `Total sentiment` group, which is why it did not show up in the ungrouped list.
  Placed in Social / Sentiment Energy.
- **`daily_trading_volume_usd` vs `volume_usd`** - answered on the Notion page:
  `daily_trading_volume_usd` is scraped from CMC and covers the exchanges CMC
  tracks; `volume_usd` is our own trading volume. This is a documentation fix,
  not a research task.
