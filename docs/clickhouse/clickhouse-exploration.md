# Overview

This documents aims at improving the reader abilities to navigate through Clickhouse using SQL and explore the available tables and their structure.

## List of tables

In order to get a list of all tables that are available execute
```sql
SHOW TABLES
```

The list of tables can be filtered by a regex.

To get the list of all tables containing `price` in their name:
```sql
SHOW TABLES LIKE '%price%'
```
```
┌─name───────────────────┐
│ asset_price_pairs_only │
│ asset_prices_v3        │
└────────────────────────┘
```

The `%` in the beginning means that there could be other characters to the left.
The `%` in the end means that there could be other characters to the right.

## Get information about a table

In order to inspect the structure of a given table one can execute the `DESCRIBE` statement:

```sql
DESCRIBE intraday_metrics
```
```
┌─name───────────────┬─type─────────────┬─default_type─┬─default_expression─────────────┬─comment─┬─codec_expression─┬─ttl_expression─┐
│ asset_id           │ UInt64           │              │                                │         │                  │                │
│ computed_at        │ DateTime         │ DEFAULT      │ now()                          │         │                  │                │
│ name               │ Nullable(String) │ DEFAULT      │ CAST(NULL, 'Nullable(String)') │         │                  │                │
│ version            │ Date             │              │                                │         │                  │                │
│ asset_ref_id       │ UInt64           │              │                                │         │                  │                │
│ ticker_slug        │ Nullable(String) │ DEFAULT      │ CAST(NULL, 'Nullable(String)') │         │                  │                │
│ decimals           │ UInt32           │ DEFAULT      │ CAST(0, 'UInt32')              │         │                  │                │
│ contract_addresses │ Array(String)    │              │                                │         │                  │                │
│ specification      │ Nullable(String) │              │                                │         │                  │                │
└────────────────────┴──────────────────┴──────────────┴────────────────────────────────┴─────────┴──────────────────┴────────────────┘
```

In order to see how a table was created one can execute the `SHOW CREATE TABLE` statement. This includes information
about the partitioning, ordering, table engine and other settings. Knowing the `ORDER BY` helps creating better and faster queries.

```sql
SHOW CREATE TABLE intraday_metrics
```
```
┌─statement──────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ CREATE TABLE default.intraday_metrics
(
    `asset_id` UInt64 CODEC(DoubleDelta, LZ4),
    `metric_id` UInt64 CODEC(DoubleDelta, LZ4),
    `dt` DateTime CODEC(DoubleDelta, LZ4),
    `value` Float64,
    `computed_at` DateTime
)
ENGINE = ReplicatedReplacingMergeTree('/clickhouse/tables/global/intraday_metrics_v2', '{hostname}', computed_at)
PARTITION BY toYYYYMM(dt)
ORDER BY (asset_id, metric_id, dt)
SETTINGS index_granularity = 8192 │
└────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```