# Overview

This document introduces the reader to the basics of Clickhouse SQL and
Santiment's database tables.

The available datasets contain two types of data:
- Precomputed metrics - Using the raw data and preprocessing, pre-computed
  metrics like `mvrv_usd` or `daily_active_addresses` are computed and stored.
- Raw data - Transfers, balances, labels, events, etc.

## Clickhouse Overview

Clickhouse SQL is identical to ANSI SQL in many ways with some distinctive
features. It supports `SELECT`, `GROUP BY`, `JOIN`, `ORDER BY`, subqueries in
`FROM`, `IN` operator and subqueries in `IN` operator, window functions, many
aggregate functions, scalar subqueries, and so on.

Clickhouse is a true Column-Oriented Database Management System that, among
other things, makes it extremely fast and suitable for storing and working with
metrics and crypto-related data expressed as time-series data.

To provide the highest possible performance, some features are not present:
- No support for foreign keys, but they are simulated in some of the
  existing tables (holding pre-computed metrics mostly). There is `asset_id` column
  and `asset_metadata` to which the `asset_id` refers. The lack of foreign key support
  means that the database cannot guarantee referential integrity, so it is enforced
  by application-level code. 
- No full-fledged transactions. The SQL Editor has read-only access, and Clickhouse is used
  mainly as append-only storage, so the lack of transactions does not cause any issues
  for this use case.

Official Clickhouse SQL Reference: https://clickhouse.com/docs/en/sql-reference/
Some of the important pages that contain useful information:
- https://clickhouse.com/docs/en/sql-reference/syntax/
- https://clickhouse.com/docs/en/sql-reference/statements/select/
- https://clickhouse.com/docs/en/sql-reference/functions/
- https://clickhouse.com/docs/en/sql-reference/operators/
- https://clickhouse.com/docs/en/sql-reference/aggregate-functions/
  
## Using pre-computed metrics

The pre-computed metrics are located in the following tables:
- `intraday_metrics` - metrics with more than one value per day. In most
  cases, these metrics have a new value every 5 minutes. Example:
  `active_addresses_24h`
- `daily_metrics_v2` - metrics that have exactly 1 value per day. Example:
  `daily_active_addresses`

All tables storing pre-computed data have a common set of columns.
- `dt` - A `DateTime`  field storing the corresponding date and time.
- `asset_id` - An `UInt64` unique identifier for an asset. The data for that id
  is stored in the `asset_metadata` table.
- `metric_id` - An `UInt64` unique identifier for metric. The data for that id
  is stored in the `metric_metadata` table.
- `value` - A `Float` column holding the metric's value for the given
  asset/metric pair.
- `computed_at` - A `DateTime` column storing the date and time when the
  given row was computed.

### Fetch data for asset bitcoin and metric **daily_active_addresses**

The following example shows how to fetch rows for Bitcoin's
`daily_active_addresses` metric:
```SQL
SELECT asset_id, metric_id, dt, value
FROM daily_metrics_v2
WHERE
    asset_id = (SELECT asset_id FROM asset_metadata FINAL PREWHERE name = 'bitcoin' LIMIT 1) AND
    metric_id = (SELECT metric_id FROM metric_metadata FINAL PREWHERE name = 'daily_active_addresses' LIMIT 1) AND
    dt >= toDateTime('2020-01-01 00:00:00')
LIMIT 2
```

```
┌─asset_id─┬─metric_id─┬─────────dt─┬──value─┐
│     1452 │        74 │ 2020-01-01 │ 522172 │
│     1452 │        74 │ 2020-01-02 │ 678391 │
└──────────┴───────────┴────────────┴────────┘
```

The query is lengthy and contains parts that will be often used in
queries - the `asset_id` and `metric_id` filtering. For this reason, predefined functions can be used to simplify fetching those ids.

```SQL
SELECT asset_id, metric_id, dt, value
FROM daily_metrics_v2
WHERE
    asset_id = get_asset_id('bitcoin') AND
    metric_id = get_metric_id('daily_active_addresses') AND
    dt >= toDateTime('2020-01-01 00:00:00')
LIMIT 2
```

The result still contains the integer representation of the asset and metric. To
convert the `asset_id` to the asset name and the `metric_id` to the metric name there are a few options:
- Join the result with the `asset_metadata` and `metric_metadata` tables. This works, but is highly verbose.
- Use
  [dictionaries](https://clickhouse.com/docs/en/sql-reference/dictionaries/external-dictionaries/external-dicts)
  that store these mappings and can be used without JOIN.

```SQL
SELECT
    dt,
    dictGetString('asset_metadata_dict', 'name', asset_id) AS asset,
    dictGetString('metric_metadata_dict', 'name', metric_id) AS metric,
    value
FROM daily_metrics_v2
WHERE
    asset_id = get_asset_id('bitcoin') AND
    metric_id = get_metric_id('daily_active_addresses') AND
    dt >= toDateTime('2020-01-01 00:00:00')
LIMIT 2
```

```
┌─────────dt─┬─asset───┬─metric─────────────────┬─value─┐
│ 2022-06-30 │ bitcoin │ daily_active_addresses │     0 │
│ 2022-07-01 │ bitcoin │ daily_active_addresses │     0 │
└────────────┴─────────┴────────────────────────┴───────┘
```

As with the `asset_id` and `metric_id` filtering, there are functions that
simplify the dictionary access as well.

```SQL
SELECT
    dt,
    get_asset_name(asset_id) AS asset,
    get_metric_name(metric_id) AS metric,
    value
FROM daily_metrics_v2
WHERE
    asset_id = get_asset_id('bitcoin') AND
    metric_id = get_metric_id('daily_active_addresses') AND
    dt >= toDateTime('2020-01-01 00:00:00')
LIMIT 2
```

To obtain the average value per month, aggregation and grouping must be used.
When grouping, all columns not part of the `GROUP BY` must have an
aggregation applied. In this case, as there is data for a single
asset and a single metric, their corresponding id columns can be aggregated with
`any` as all these values are the same.

```SQL
SELECT
    toStartOfMonth(dt) AS month,
    get_asset_name(ANY(asset_id)) AS asset,
    get_metric_name(ANY(metric_id)) AS metric,
    FLOOR(AVG(value)) AS monthly_avg_value
FROM daily_metrics_v2
WHERE
    asset_id = get_asset_id('bitcoin') AND
    metric_id = get_metric_id('daily_active_addresses') AND
    dt >= toDateTime('2020-01-01 00:00:00')
GROUP BY month
LIMIT 12
```

```
┌──────month─┬─asset───┬─metric─────────────────┬─monthly_avg_value─┐
│ 2020-01-01 │ bitcoin │ daily_active_addresses │            712767 │
│ 2020-02-01 │ bitcoin │ daily_active_addresses │            758896 │
│ 2020-03-01 │ bitcoin │ daily_active_addresses │            738555 │
│ 2020-04-01 │ bitcoin │ daily_active_addresses │            803423 │
│ 2020-05-01 │ bitcoin │ daily_active_addresses │            896321 │
│ 2020-06-01 │ bitcoin │ daily_active_addresses │            876348 │
│ 2020-07-01 │ bitcoin │ daily_active_addresses │            958904 │
│ 2020-08-01 │ bitcoin │ daily_active_addresses │            984239 │
│ 2020-09-01 │ bitcoin │ daily_active_addresses │            982237 │
│ 2020-10-01 │ bitcoin │ daily_active_addresses │            942581 │
│ 2020-11-01 │ bitcoin │ daily_active_addresses │           1026279 │
│ 2020-12-01 │ bitcoin │ daily_active_addresses │           1072016 │
└────────────┴─────────┴────────────────────────┴───────────────────┘
```

### Using precomputed metrics to build new metrics

Not all metrics are build from the raw data only. Some of the metrics are
computed by combining a set of pre-computed metrics.

The MVRV is defined as the ratio between the Market Value and Realized Value.
The total supply is part of the nominator and the denominator, so it can be
eliminated. The result is that the nominator is just `price_usd` and the
denominator is `realized_price_usd`. There are precomputed metrics for both, so
we can use them to compute the MVRV (and that's how we do it for the official
MVRV metric!). Depending on the load on the database, the query duration can
vary. At the moment of writing this, running the query takes 0.13 seconds.

```sql
SELECT
  dt,
  get_asset_name(any(asset_id)) AS asset,
  argMaxIf(value, (dt, computed_at), metric_id=get_metric_id('price_usd')) AS nominator,
  argMaxIf(value, (dt, computed_at), metric_id=get_metric_id('mean_realized_price_usd_intraday_20y')) AS denominator,
  nominator / denominator AS mvrv_usd_ratio,
  FLOOR((mvrv_usd_ratio - 1) * 100, 2) AS mvrv_usd_percent
FROM intraday_metrics
WHERE
  asset_id = get_asset_id('bitcoin') AND
  metric_id IN (get_metric_id('price_usd'), get_metric_id('mean_realized_price_usd_intraday_20y')) AND
  dt >= toDateTime('2022-01-01 00:00:00')
GROUP BY dt
ORDER BY dt ASC
LIMIT 10
```

```
┌──────────────────dt─┬──────────price_usd─┬─realized_price_usd─┬─────mvrv_usd_ratio─┬─mvrv_usd_percent─┐
│ 2022-01-01 00:00:00 │  46378.15778582922 │  23026.68649269964 │ 2.0141047128310414 │           101.41 │
│ 2022-01-01 00:05:00 │   46418.9618983969 │  23026.68649269964 │  2.015876748620064 │           101.58 │
│ 2022-01-01 00:10:00 │  46376.92099283003 │  23026.68736678082 │    2.0140509250903 │            101.4 │
│ 2022-01-01 00:15:00 │  46333.90243842331 │  23026.68736678082 │  2.012182720874839 │           101.21 │
│ 2022-01-01 00:20:00 │  46365.91591529093 │  23026.62194196269 │ 2.0135787191084136 │           101.35 │
│ 2022-01-01 00:25:00 │  46418.47006354396 │ 23026.590133451697 │  2.015863825018099 │           101.58 │
│ 2022-01-01 00:30:00 │   46433.0344984134 │ 23026.601073686023 │ 2.0164953720189045 │           101.64 │
│ 2022-01-01 00:35:00 │  46502.41393773127 │ 23026.619212135225 │ 2.0195067938251263 │           101.95 │
│ 2022-01-01 00:40:00 │  46564.63864446795 │  23026.62694351816 │ 2.0222084093639072 │           102.22 │
│ 2022-01-01 00:45:00 │ 46668.585782409915 │  23026.71967910803 │  2.026714461841127 │           102.67 │
└─────────────────────┴────────────────────┴────────────────────┴────────────────────┴──────────────────┘
```

To return only some of the columns, the query can be provided as a FROM subquery. This does not induce any
performence degradation:

```sql
WITH
    get_metric_id('price_usd') AS price_usd_metric_id,
    get_metric_id('mean_realized_price_usd_intraday_20y') AS realized_price_usd_metric_id
SELECT
    dt, 
    price_usd / realized_price_usd AS mvrv_usd_ratio,
    FLOOR((mvrv_usd_ratio - 1) * 100, 2) AS mvrv_usd_percent
FROM (
  SELECT
    dt,
    get_asset_name(any(asset_id)) AS asset,
    argMaxIf(value, (dt, computed_at), metric_id=price_usd_metric_id) AS price_usd,
    argMaxIf(value, (dt, computed_at), metric_id=realized_price_usd_metric_id) AS realized_price_usd
  FROM intraday_metrics
  WHERE
    asset_id = get_asset_id('bitcoin') AND
    metric_id IN (price_usd_metric_id, realized_price_usd_metric_id) AND
    dt >= toDateTime('2022-01-01 00:00:00')
  GROUP BY dt
)
ORDER BY dt ASC
LIMIT 10
```

The following row needs some explanation:
```sql
argMaxIf(value, (dt, computed_at), metric_id=get_metric_id('price_usd')) AS price_usd,
```

This function call has three parameters:
- `value` - This is the column that is returned
- `(dt, computed_at)` - This is a tuple, consisting of two columns. In the given
  group (as per `GROUP BY`) get the value that has the latest `dt` and if there
  are more than one such value - get the one with the latest `computed_at`.
- `metric_id=get_metric_id('price_usd')` - This a boolean expression. Look only
  at the rows for which the expression evaluates to true.

> Note: In Clickhouse values are not directly updated. If a value needs to be
> updated, a new record with the same key is inserted (if the table engine is of
> MergeTree type) and at some point Clickhouse merges both rows into one. The
> daily metrics are computed every hour, so for the current day there could be
> multiple rows with the same date. In order to get the last one, getting the
> one with the biggest `computed_at` is required.

## Using raw data

### Examples for address balance

