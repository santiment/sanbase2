# Overview

The available datasets contain two types of data:
- Precomputed metrics - Using the raw data and preprocessing, precomputed
  metrics like `mvrv_usd` or `daily_active_addresses` are computed and stored.
- Raw data - Transfers, balances, etc.

The precomputed metrics are located in the following tables:
- `intraday_metrics` - metrics that have more than 1 value per day. In most
  cases these metrics have a new value every 5 minutes. Example:
  `active_addresses_24h`
- `daily_metrics_v2` - metrics that have exactly 1 value per day. Example:
  `daily_active_addresses`

## Clickhouse Basics

TODO

## Using precomputed metrics

All tables storing precomputed data have a common set of columns.
- `dt` - A `DateTime`  field storing the corresponding date and time.
- `asset_id` - An `UInt64` unique identifier for an asset. The data for that id
  is stored in the `asset_metadata` table.
- `metric_id` - An `UInt64` unique identifier for anmetric. The data for that id
  is stored in the `metric_metadata` table.
- `value` - A `Float` columns that holds the value of the metric for the given
  asset/metric pair.
- `computed_at` - A `DateTime` field that stores the date and time when the
  given row was computed.

### Fetch data for asset bitcoin and metric **daily_active_addresses**

The following example shows how to fetch rows for Bitcoin's
`daily_active_addresses` metric:
```sql
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

The above shown query is verbose and contains parts that will be often used in
queries - the `asset_id` and `metric_id` filtering. For this reason there are
predefined functions that can be used to simplify fetching those ids.

```sql
SELECT asset_id, metric_id, dt, value
FROM daily_metrics_v2
WHERE
    asset_id = get_asset_id('bitcoin') AND
    metric_id = get_metric_id('daily_active_addresses') AND
    dt >= toDateTime('2020-01-01 00:00:00')
LIMIT 2
```

The result still contains the integer representation of the asset and metric. To
convert the `asset_id` to the asset name and the `metric_id` to the metric name
there are a few options:
- Join the result with the `asset_metadata` and `metric_metadata` tables. This
  works, but is extremely verbose.
- Use
  [dictionaries](https://clickhouse.com/docs/en/sql-reference/dictionaries/external-dictionaries/external-dicts)
  that store these mappings and can be used without JOIN.

```sql
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

```sql
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
When grouping, all columns that are not part of the `GROUP BY` must have an
aggregation applied to them. In this case, as there there is data for a single
asset and a single metric, their corresponding id columns can be aggregated with
`any` as all of these values are the same.

```sql
SELECT
    toStartOfMonth(dt) AS month,
    get_asset_name(any(asset_id)) AS asset,
    get_metric_name(any(metric_id)) AS metric,
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