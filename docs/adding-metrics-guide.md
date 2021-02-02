# Adding Metrics Guide

Serving metrics is one of the main tasks done by the GraphQL API server. Metrics
are also used internally for computing alerts and for computing other metrics
and checks.

## Some history

Over time, the drawbacks of having a separate Elixir function and GraphQL query
for every metric, each having different field names (price_usd, nvt,
transaction_volume, etc.) made it so adding new metrics was slow and repetitive
process. Another important drawback was that adding new metrics could be done
only by a backend developer who knew the project. The remanants of this approach
can still be seen in the `etherbi_resolver.ex`, `clickhouse_resolver.ex` and
their corresponding type/queries modules.

Apart from the Elixir part, the database tables evolved in a similar direction
as well. Now all metrics are stored in a handful of tables with similar schema,
so fetching the data can be done by a single SQL query (with a few dynamic
parts)

## Current status

Apart from a few metrics that have still not been migrated, all metrics are
served by the [Sanbase.Metric](../lib/sanbase/metric/metric.ex) module and the
[get_metric](../lib/sanbase_web/graphql/resolvers/metric_resolver.ex) GraphQL
query.

The `Sanbase.Metric` module does not do the actual metric fetching but only
dispatches to the proper metric adapter module or aggregates data from the
metric adapter modules.

The true metric and metric metdata fetching is done by the so-called
`MetricAdapter` modules. A few examples for such modules are the [Clickhouse
MetricAdapter](../lib/sanbase/clickhouse/metric/metric_adapter.ex), [Github
MetricAdapter](../lib/sanbase/clickhouse/github/metric_adapter.ex) or [Price
MetricAdapter](../lib/sanbase/prices/metric_adapter.ex).

The Clickhouse MetricAdapter is the biggest, most complex with the most SQL
queries written. It also serves the biggest amount of metrics.

> At time of writing this, there **601** metrics served by the `Sanbase.Metric` module
and **551** of those are coming from the Clickhouse MetricAdapter.

## Adding new metrics

Adding new metrics does not require modifying neither the metric module nor the
resolver. Every MetricAdapter is responsible for a different source of metric.
This can be a different database, internal service API or just a table with a
different format than any of the others.

### Clickhouse MetricAdapter

When adding a new metric, the first thing to decide is whether the metric is
*timeseries* or *histogram*. Timeseries metrics are all metrics that are
represented as `{datetime, number}` pairs. Histogram metrics do not have a
specific format - they can vary from `{string, number}` pairs, `{string, string,
number}` pairs, `{[datetime, datetime], string}` pairs, etc.

The first step is to add a JSON map describing the metric in one of the JSON
files in the `../lib/sanbase/clickhouse/metric/metric_files` directory. If there
is no proper JSON file do define the new metric, a new JSON file can be created
and injected in the [file
handler](../lib/sanbase/clickhouse/metric/file_handler.ex) file by adding a new
line like:

```elixir
@external_resource Path.join(__DIR__, "metric_files/new_metrics_file.json")
```

If the metric added is a timeseries metric then defining the JSON map is all
that needs to be done apart from [adding the metric to the tests](#adding-tests).

A JSON map describing a metric looks like this:

```json
{
  "human_readable_name": "Age Consumed",
  "name": "age_consumed",
  "metric": "stack_age_consumed_5min",
  "version": "2019-01-01",
  "access": "restricted",
  "selectors": ["slug"],
  "min_plan": {
    "SANAPI": "free",
    "SANBASE": "free"
  },
  "aggregation": "sum",
  "min_interval": "5m",
  "table": "intraday_metrics",
  "has_incomplete_data": false,
  "data_type": "timeseries"
}
```

- `human_readable_name` - Shows how the metric will be displayed in places where
  a human readable name is needed like the payload of an alert
- `name` - The name with which the metric will be exposed in the
  `Sanbase.Metric` module and public API.
- `metric` - The name of the metric used internally in the database. This should
  correspond to a row in the `metric_metadata` Clickhouse table.
- `version` - The `version` of the metric stored in the `metric_metadata`
  Clickhouse table
- `access` - `free` or `restricted`. If `restricted` is chosen, the access will
  be restricted based on the subscription plan the user has.
- `selectors` - How to uniquely identify the metric in the database. Metrics
  like price are uniquely identified by the project slug. Other metrics might
  have labels and/or other columns that form the unique key.
- `min_plan` - Requires two fields - `SANAPI` and `SANBASE`. It choose the
  minimal subscription plan for which the metric is accessible. If instead of
  `free`, the value is `pro` the metric will be visible only to users with `pro`
  or higher subscription plan.
- `aggregation` - The default aggregation which is used if many data points are
  used to determine a single value. For example if `price_usd` metric is fetched
  with a daily interval, the `aggregation` will choose whether to show the
  average/min/max/highest/lowest/first/last/etc. price for that day.
- `min_interval` - What is the granularity of the data in the database. There
  are mainly daily metrics with 1 value per day available and intraday metrics
  with 1 value per 5 minutes/1 hour/etc.
- `table` - The table in which the metric is stored
- `has_incomplete_data` - Mostly used for daily metrics. Shows whether the last
  data point stored is computed by not having all the necessary data and can
  change. For example fetching the `daily_active_addresses` for today cannot
  include the full day data before the next day comes. The value of
  `daily_active_addresses` for today will include only data for 1 hour, 2 hours,
  3 hours, and so until the day finishes.
- `data_type` - `"timeseries"` or `"histogram"`

Adding a new histogram metric is more complicated. A few steps must be done:

- Add a function header matching the new metric name in
  `Sanbase.Clickhouse.MetricAdapter.HistogramMetric`
- Add an SQL query for this new metric and use it in this new function
- If the result format does not match any of the existing formats in the [metric
  types](../lib/sanbase_web/graphql/schema/types/metric_types.ex) (in the
  `:value_list` union), a new type must be added as well as extending the
  `resolve_type` function argument.

## Adding Tests

The metric must be added in the proper list (free or restricted) in the
`MetricAccessLevelTest` test. Furthermore, if needed, separate tests for this
metric can be added.