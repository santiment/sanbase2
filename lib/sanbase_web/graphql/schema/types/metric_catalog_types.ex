defmodule SanbaseWeb.Graphql.MetricCatalogTypes do
  use Absinthe.Schema.Notation

  @desc ~s"""
  A single row of the public metrics directory: the metric, how to read it and
  where its category places it.
  """
  object :metric_catalog_entry do
    @desc "The name used as the `metric` argument of the `getMetric` query."
    field(:metric, non_null(:string))

    @desc "A human readable name of the metric."
    field(:human_readable_name, :string)

    @desc ~s"""
    The name of the category the metric belongs to, for example `Social` or
    `On-chain Labels`. Null when the metric is not categorized yet.
    """
    field(:category_name, :string)

    @desc ~s"""
    The name of the group inside the category, for example `Social Volume`.
    Null when the metric is categorized but not grouped.
    """
    field(:group_name, :string)

    @desc ~s"""
    The minimal granularity for which the data is available, which is also the
    cadence at which the metric is refreshed.
    """
    field(:min_interval, :string)

    @desc "Links to the documentation of the metric."
    field(:docs, list_of(:metric_documentation))

    @desc ~s"""
    A deprecated metric should not be used anymore as it is going to be removed
    in the future. Deprecated metrics are excluded from the listing unless
    `includeDeprecated: true` is provided.
    """
    field(:is_deprecated, non_null(:boolean))

    @desc "The status of the metric."
    field(:status, :string)
  end

  object :metric_catalog do
    @desc ~s"""
    The total number of metrics matching the filters, ignoring pagination.
    Use it together with the length of `metrics` to render a
    "showing X of Y metrics" counter.
    """
    field(:total_count, non_null(:integer))

    @desc "The metrics on the requested page."
    field(:metrics, list_of(:metric_catalog_entry))
  end

  object :metric_catalog_group do
    field(:name, non_null(:string))
    field(:short_description, :string)
    field(:display_order, :integer)

    @desc "The number of metrics in this group."
    field(:metrics_count, non_null(:integer))
  end

  object :metric_catalog_category do
    field(:name, non_null(:string))
    field(:short_description, :string)
    field(:description, :string)
    field(:display_order, :integer)

    @desc "The number of metrics in this category, across all its groups."
    field(:metrics_count, non_null(:integer))

    field(:groups, list_of(:metric_catalog_group))
  end
end
