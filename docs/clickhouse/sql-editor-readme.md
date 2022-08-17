# Overview

This document introduces the reader to the basics of Clickhouse SQL and
Santiment's datasets.

The available datasets contain two types of data:
- Precomputed metrics - Using the raw data and preprocessing, pre-computed
  metrics like `mvrv_usd` or `daily_active_addresses` are computed and stored.
- Raw data - Transfers, balances, labels, events, etc.

## Clickhouse Overview

[Clickhouse](https://clickhouse.com/) is a true Column-Oriented Database Management System that, among
other things, makes it extremely fast and suitable for storing and working with
metrics and crypto-related data.

Clickhouse SQL is identical to ANSI SQL in many ways with some distinctive
features. It supports `SELECT`, `GROUP BY`, `JOIN`, `ORDER BY`, subqueries in
`FROM`, `IN` operator and subqueries in `IN` operator, window functions, many
aggregate functions (avg, max, min, last, first, etc.), scalar subqueries, and so on.

To provide the highest possible performance, some features are not present:
- No support for foreign keys, but they are simulated in some of the existing
  tables (holding pre-computed metrics mostly). For example, there is `asset_id`
  column in the `intraday_metrics` table, and `asset_metadata` table to which
  the `asset_id` refers. The lack of foreign key support means that the database
  cannot guarantee referential integrity, so it is enforced by application-level
  code. 
- No full-fledged transactions. The SQL Editor has read-only access, and
  Clickhouse is used mainly as append-only storage, so the lack of transactions
  does not cause any issues
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

### The FINAL keyword

> Note: This part is more technical

Values in Clickhouse tables are not updated directly. Instead, in case there is a need to
modify an existing row, the [MergeTree Table Engine](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/mergetree/) is used.
In order to update an existing row, a new row with the same primary key is
inserted. At some unspecified point in time, Clickhouse will merge all rows with
the same primary key into one. Until that merge happens, all rows will exist and
will appear in selects.

Example: There is one value per day for an asset-metric pair in the
`daily_metrics_v2` table. The value is recomputed every hour and a new row with
the same primary key but different `value` and `computed_at` is inserted.

In order to read the data as if it is already merged, you need to add the
`FINAL` keyword after the table name: 
```sql
SELECT dt, value
FROM daily_metrics_v2 FINAL
WHERE asset_id = get_asset_id('bitcoin') AND  metric_id = get_metric_id('daily_active_addresses')
ORDER BY dt DESC
LIMIT 2
```

This `FINAL` keyword is not free - it slightly reduces the performance. In case performance is seeked, the same goal can be
achieved with standard SQL by using `GROUP BY` the primary key and aggregate functions. This approach has smaller performance penalty at the cost of code readability and maintainability.
```sql
SELECT dt, argMax(value, computed_at)
FROM daily_metrics_v2
WHERE asset_id = get_asset_id('bitcoin') AND  metric_id = get_metric_id('daily_active_addresses')
GROUP BY dt, asset_id, metric_id
ORDER BY dt DESC
LIMIT 2
```

### The PREWHERE clause

In addition to the standard [WHERE](https://clickhouse.com/docs/en/sql-reference/statements/select/where) clause, Clickhouse also supports [PREWHERE](https://clickhouse.com/docs/en/sql-reference/statements/select/prewhere/).
This is an optimization to apply filtering more efficiently. The effect is that,
at first only the columns necessary for executing the filtering expression are
read.

In case `FINAL` keyword is not used, `WHERE` is automatically transformed into
`PREWHERE`. In case `FINAL` keyword is used, `WHERE` is not automatically
transformed into `PREWHERE`. Such transformation in the latter case can lead to
different results in case columns that are not part of the primary key are used
in the filtering.

Do not use `PREWHERE` unless you are sure what you are doing.

### Fetch data for asset bitcoin and metric **daily_active_addresses**

The following example shows how to fetch rows for Bitcoin's
`daily_active_addresses` metric:
```SQL
SELECT asset_id, metric_id, dt, value
FROM daily_metrics_v2 FINAL
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
FROM daily_metrics_v2 FINAL
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
FROM daily_metrics_v2 FINAL
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
FROM daily_metrics_v2 FINAL
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
    get_asset_name(any(asset_id)) AS asset,
    get_metric_name(any(metric_id)) AS metric,
    floor(avg(value)) AS monthly_avg_value
FROM daily_metrics_v2 FINAL
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

In the query `anyIf` is used as there is filtering by `asset_id` and `metric_id`,
so there is only one value per metric for each `dt`. The example after that discusses
how to handle more complex `GROUP BY` clauses.

```sql
SELECT
  dt,
  get_asset_name(any(asset_id)) AS asset,
  anyIf(value, metric_id=get_metric_id('price_usd')) AS nominator,
  anyIf(value, metric_id=get_metric_id('mean_realized_price_usd_intraday_20y')) AS denominator,
  nominator / denominator AS mvrv_usd_ratio,
  floor((mvrv_usd_ratio - 1) * 100, 2) AS mvrv_usd_percent
FROM intraday_metrics FINAL
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
performence degradation. This example also shows how the [WITH Clause](https://clickhouse.com/docs/en/sql-reference/statements/select/with/)
can be used to avoid string literals repetition.

```sql
WITH
    get_metric_id('price_usd') AS price_usd_metric_id,
    get_metric_id('mean_realized_price_usd_intraday_20y') AS realized_price_usd_metric_id
SELECT
    dt, 
    price_usd / realized_price_usd AS mvrv_usd_ratio,
    floor((mvrv_usd_ratio - 1) * 100, 2) AS mvrv_usd_percent
FROM (
  SELECT
    dt,
    get_asset_name(any(asset_id)) AS asset,
    anyIf(value, metric_id=price_usd_metric_id) AS price_usd,
    anyIf(value, metric_id=realized_price_usd_metric_id) AS realized_price_usd
  FROM intraday_metrics FINAL
  WHERE
    asset_id = get_asset_id('bitcoin') AND
    metric_id IN (price_usd_metric_id, realized_price_usd_metric_id) AND
    dt >= toDateTime('2022-01-01 00:00:00')
  GROUP BY dt
)
ORDER BY dt ASC
LIMIT 10
```

The next query demonstrates what needs to be done if there is a need to
aggregate the datetime instead of getting a value for each `dt`:

```sql
WITH
    get_metric_id('price_usd') AS price_usd_metric_id,
    get_metric_id('mean_realized_price_usd_intraday_20y') AS realized_price_usd_metric_id
SELECT
    month, 
    price_usd / realized_price_usd AS mvrv_usd_ratio,
    floor((mvrv_usd_ratio - 1) * 100, 2) AS mvrv_usd_percent
FROM (
  SELECT
    toStartOfMonth(dt) AS month,
    get_asset_name(any(asset_id)) AS asset,
    argMaxIf(value, dt, metric_id=price_usd_metric_id) AS price_usd,
    argMaxIf(value, dt, metric_id=realized_price_usd_metric_id) AS realized_price_usd
  FROM intraday_metrics FINAL
  WHERE
    asset_id = get_asset_id('bitcoin') AND
    metric_id IN (price_usd_metric_id, realized_price_usd_metric_id) AND
    dt >= toDateTime('2022-01-01 00:00:00')
  GROUP BY month
)
ORDER BY month ASC
LIMIT 10
```

The following row needs some explanation:
```sql
argMaxIf(value, dt, metric_id=get_metric_id('price_usd')) AS price_usd,
```

This function call has three parameters:
- `value` - This is the column that is returned
- `dt` - This is the column that `max` is performed upon. Of all columns matching the filter, the one with the max `dt` is returned.
- `metric_id=get_metric_id('price_usd')` - This a boolean expression. Look only
  at the rows for which the expression evaluates to true.

If the `FINAL` keyword is not used, taking the row with biggest `computed_at` among those
with the same `dt` can be achieved by using a tuple as a second argument:

```sql
argMaxIf(value, (dt, computed_at), metric_id=get_metric_id('price_usd')) AS price_usd,
```

## Using raw data

Get the UNI balance changes for an address

### Example for top transfers

Find the 5 biggest ETH transactions to the graveyard address 0x0000000000000000000000000000000000000000

> There are some duplicated tables with different `ORDER BY`. In the case of transfer tables there are
> tables with the `_to` suffix. This indicates that the `to` address is to the front of the `ORDER BY`
> key. This table has bigger performance when only filtering of `to` address is applied.

```sql
SELECT
    dt,
    from,
    transactionHash,
    value / pow(10, 18) -- transform from gwei to ETH
FROM eth_transfers_to FINAL
WHERE to = '0x0000000000000000000000000000000000000000'
ORDER BY value DESC
LIMIT 5
```

```sql
┌──────────────────dt─┬─from───────────────────────────────────────┬─transactionHash────────────────────────────────────────────────────┬─divide(value, pow(10, 18))─┐
│ 2015-08-08 11:01:14 │ 0x3f98e477a361f777da14611a7e419a75fd238b6b │ 0x242a15349ad0a7070afb73df92e8e569fd196c88c7f589a467f24e6028a07c69 │                       2000 │
│ 2016-07-28 19:39:05 │ 0xaa1a6e3e6ef20068f7f8d8c835d2d22fd5116444 │ 0x1c96608bda6ce4be0d0f30b3a5b3a9d9c94930291a168a0dbddfe9be24ac70d1 │                       1493 │
│ 2015-08-13 17:50:09 │ 0xf5437e158090b2a2d68f82b54a5864b95dd6dbea │ 0x88db76f50553d3d9d61eaf7480a92b1d68db08d69e688fd9b457571cc22ab2b0 │                       1000 │
│ 2021-09-08 03:30:47 │ 0x517bb391cb3a6d879762eb655e48a478498c3698 │ 0x429bfa5fdd1bf8117d6707914b6300ccf08ec3383d38a10ddf37247e18d90557 │              515.001801432 │
│ 2015-08-15 06:52:11 │ 0x20134cbff88bfadc466b52eceaa79857891d831e │ 0xe218f7abd6b557e01376c57bcdf7f5d8e94e0760306b1d9eb37e1a8ddc51e6ab │                        400 │
└─────────────────────┴────────────────────────────────────────────┴────────────────────────────────────────────────────────────────────┴────────────────────────────┘
```

### Example for address balance

Select the UNI balance of address at the beginning of each month.

For performance reasons the table has a non-intuitive design. The balances of an address
are stored in a single field of type `AggregateFunction(groupArray, Tuple(DateTime, Float64))`.
When the `groupArrayMerge` function is called on that field, it essentially turns into
`Array<Tuple(DateTime, Float64)>`

The [arrayJoin](https://clickhouse.com/docs/en/sql-reference/functions/array-join/) is a Clickhouse-specific function that is useful in many
scenarios. Normal functions do not change a set of rows, but just change the
values in each row (map). Aggregate functions compress a set of rows (fold or
reduce). The arrayJoin function takes each row and generates a set of rows
(unfold).

In this scenario `arrayJoin` is used to unfold the array of tuples into rows where each row has a datetime and value.

```sql
SELECT
  toStartOfMonth(dt) AS datetime,
  toFloat64(argMax(value, dt)) / pow(10, 18) AS value
FROM (
  SELECT
    arrayJoin(groupArrayMerge(values)) AS values_merged,
    values_merged.1 AS dt,
    values_merged.2 AS value
  FROM balances_aggregated
  WHERE
    address = '0x1a9c8182c09f50c8318d769245bea52c32be35bc' AND
    blockchain = 'ethereum' AND
    asset_ref_id = get_asset_ref_id('uniswap')
  GROUP BY address, blockchain, asset_ref_id
  HAVING dt >= toDateTime('2021-01-01 00:00:00') AND dt < toDateTime('2022-08-01 00:00:00')
)
GROUP BY datetime
```

Note that not every month has a balance. This is because during these months no transfers happened and balance records
are produced only when the balance changes.

```sql
┌───datetime─┬──────────────value─┐
│ 2021-01-01 │   54854034.6123795 │
│ 2021-02-01 │   75792689.3561644 │
│ 2021-04-01 │ 105258204.83054289 │
│ 2021-05-01 │ 113312234.63774733 │
│ 2021-06-01 │ 123442268.88432267 │
│ 2021-07-01 │ 134441434.15575847 │
│ 2021-08-01 │  158560087.2506342 │
│ 2021-09-01 │ 173403155.20471838 │
│ 2021-11-01 │ 173403155.20471838 │
│ 2021-12-01 │ 173403155.20471838 │
│ 2022-02-01 │  227551085.1894977 │
│ 2022-04-01 │  227040881.1894977 │
│ 2022-05-01 │ 254925338.09589037 │
│ 2022-06-01 │  268638940.6453577 │
│ 2022-07-01 │  280393165.7214612 │
└────────────┴────────────────────┘
```

## Example for Development Activity

The `github_v2` table contains [Github Events](https://docs.github.com/en/developers/webhooks-and-events/events/github-event-types) data.
Using these events one can compute better development activity metrics compared to using just commits counts, as described in [this article](https://medium.com/santiment/tracking-github-activity-of-crypto-projects-introducing-a-better-approach-9fb1af3f1c32)

To compute the development activity of an organization:

```sql
WITH ('IssueCommentEvent',
      'IssuesEvent',
      'ForkEvent',
      'CommitCommentEvent',
      'FollowEvent',
      'ForkEvent',
      'DownloadEvent',
      'WatchEvent',
      'ProjectCardEvent',
      'ProjectColumnEvent',
      'ProjectEvent') AS non_dev_related_event_types
SELECT
  toStartOfMonth(dt) AS month,
  count(*) AS events
FROM (
  SELECT event, dt
  FROM github_v2 FINAL
  WHERE
    owner = 'santiment' AND
    dt >= toDateTime('2021-01-01 00:00:00') AND
    dt < toDateTime('2021-12-31 23:59:59') AND
    event NOT IN non_dev_related_event_types -- these events are related more with comments/issues, not developing
)
GROUP BY month
```

```
┌──────month─┬─events─┐
│ 2021-01-01 │   1600 │
│ 2021-02-01 │   1815 │
│ 2021-03-01 │   1709 │
│ 2021-04-01 │   1541 │
│ 2021-05-01 │   1139 │
│ 2021-06-01 │   1211 │
│ 2021-07-01 │   1213 │
│ 2021-08-01 │   1058 │
│ 2021-09-01 │   1156 │
│ 2021-10-01 │    269 │
│ 2021-11-01 │   1079 │
│ 2021-12-01 │    760 │
└────────────┴────────┘
```

To count all the people that have contributed to the development activity of an organization in a given
time period:

```sql
WITH ('IssueCommentEvent',
      'IssuesEvent',
      'ForkEvent',
      'CommitCommentEvent',
      'FollowEvent',
      'ForkEvent',
      'DownloadEvent',
      'WatchEvent',
      'ProjectCardEvent',
      'ProjectColumnEvent',
      'ProjectEvent') AS non_dev_related_event_types
SELECT
  toStartOfMonth(dt) AS month,
  uniqExact(actor) AS contributors
FROM (
  SELECT actor, dt
  FROM github_v2 FINAL
  WHERE
    owner = 'santiment' AND
    dt >= toDateTime('2021-01-01 00:00:00') AND
    dt < toDateTime('2021-12-31 23:59:59') AND
    event NOT IN non_dev_related_event_types -- these events are related more with comments/issues, not developing
)
GROUP BY month
```

```
┌──────month─┬─contributors─┐
│ 2021-01-01 │           18 │
│ 2021-02-01 │           17 │
│ 2021-03-01 │           20 │
│ 2021-04-01 │           22 │
│ 2021-05-01 │           23 │
│ 2021-06-01 │           19 │
│ 2021-07-01 │           21 │
│ 2021-08-01 │           20 │
│ 2021-09-01 │           20 │
│ 2021-10-01 │           19 │
│ 2021-11-01 │           19 │
│ 2021-12-01 │           19 │
└────────────┴──────────────┘
```