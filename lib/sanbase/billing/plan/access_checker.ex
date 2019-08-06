defmodule Sanbase.Billing.Plan.AccessChecker do
  @moduledoc """
  Module that contains functions for determining access based on the subscription
  plan.

  Adding new queries or updating the subscription plan does not require this
  module to be changed.

  The subscription plan needed for a given query is given in the query definition
    ```
    field :network_growth, list_of(:network_growth) do
        meta(access: :restricted)
        ...
    end
    ```

  This module knows how to inspect the GraphQL schema that is being build
  compile-time and build the needed sets of data also compile time. There are no
  checks for mutations - mutations

  Additionally, this module will raise a compile-time warning if there is a
  query without a subscription plan defined.

  The actual historical/realtime restrictions are implemented in modules:
  - ApiAccessChecker
  - SanbaseAccessChecker
  as we have different restrictions.
  """

  alias Sanbase.Billing.Product
  alias Sanbase.Billing.Plan.CustomAccess

  alias Sanbase.Billing.Plan.{
    ApiAccessChecker,
    SanbaseAccessChecker,
    SansheetsAccessChecker
  }

  defmodule Helper do
    @moduledoc ~s"""
    Contains a single function `get_metrics_with_subscription_plan/1` that examines
    the Absinthe's compile-time build schema.

    It is a different module because functions from the module where a module
    attribute is defined cannot be used
    """
    alias Sanbase.Clickhouse.Metric
    require SanbaseWeb.Graphql.Schema

    @mutation_type Absinthe.Schema.lookup_type(SanbaseWeb.Graphql.Schema, :mutation)
    @mutations_mapset MapSet.new(@mutation_type.fields |> Map.keys())

    @query_type Absinthe.Schema.lookup_type(SanbaseWeb.Graphql.Schema, :query)
    @fields @query_type.fields |> Map.keys()
    def get_metrics_with_access_level(level) do
      from_schema =
        Enum.filter(@fields, fn f ->
          Map.get(@query_type.fields, f) |> Absinthe.Type.meta(:access) == level
        end)

      clickhouse_v2_metrics =
        Enum.filter(Metric.metric_access_map(), fn {_metric, metric_level} ->
          level == metric_level
        end)
        |> Enum.map(fn {metric, _access} -> {:clickhouse_v2_metric, metric} end)

      from_schema ++ clickhouse_v2_metrics
    end

    def get_metrics_without_access_level() do
      get_metrics_with_access_level(nil) -- [:__typename, :__type, :__schema]
    end

    def mutations_mapset(), do: @mutations_mapset
  end

  # Raise an error if there is any query without subscription plan
  case Helper.get_metrics_without_access_level() do
    [] ->
      :ok

    queries ->
      require Sanbase.Break, as: Break

      Break.break("""
      There are GraphQL queries defined without specifying their access level.
      The access level could be either `free` or `restricted`.

      Queries without access level: #{inspect(queries)}
      """)
  end

  @free_metrics Helper.get_metrics_with_access_level(:free)
  @free_metrics_mapset MapSet.new(@free_metrics)
  def free_metrics_mapset(), do: @free_metrics_mapset

  @restricted_metrics Helper.get_metrics_with_access_level(:restricted)
  @restricted_metrics_mapset MapSet.new(@restricted_metrics)
  def restricted_metrics_mapset(), do: @restricted_metrics_mapset

  @all_metrics @free_metrics ++ @restricted_metrics
  def all_metrics, do: @all_metrics

  @custom_access_queries_stats CustomAccess.get()
  @custom_access_queries @custom_access_queries_stats |> Map.keys() |> Enum.sort()

  # Raise an error if there are queries with custom access logic that are marked
  # as free. If there are such queries the access restriction logic will never
  # be applied

  case @custom_access_queries -- @restricted_metrics do
    [] ->
      :ok

    queries ->
      require Sanbase.Break, as: Break

      Break.break("""
      There are queries with access level `:free` that are defined in the
      CustomAccess module. These queries custom access logic will never be
      executed.

      Queries defined in the CustomAccess module but do not have the `:restricted`
      access level field: #{inspect(queries)}.

      """)
  end

  @doc ~s"""
  Check if a query full access is given only to users with a plan higher than free.
  A query can be restricted but still accessible by not-paid users or users with
  lower plans. In this case historical and/or realtime data access can be cut off
  """
  def is_restricted?(query), do: query in @restricted_metrics_mapset

  def custom_access_queries_stats, do: @custom_access_queries_stats
  def custom_access_queries, do: @custom_access_queries

  @product_to_access_module [
    {Product.product_api(), ApiAccessChecker},
    {Product.product_sanbase(), SanbaseAccessChecker},
    {Product.product_sheets(), SansheetsAccessChecker},
    {Product.product_sangraphs(), SanbaseAccessChecker}
  ]

  def historical_data_in_days(plan, query, _product) when query in @custom_access_queries do
    Map.get(@custom_access_queries_stats, query)
    |> get_in([:plan_access, plan, :historical_data_in_days])
  end

  def realtime_data_cut_off_in_days(plan, query) when query in @custom_access_queries do
    Map.get(@custom_access_queries_stats, query)
    |> get_in([:plan_access, plan, :realtime_data_cut_off_in_days])
  end

  for {product, module} <- @product_to_access_module do
    def historical_data_in_days(plan, query, unquote(product)) do
      unquote(module).historical_data_in_days(plan, query)
    end

    def realtime_data_cut_off_in_days(plan, query, unquote(product)) do
      unquote(module).realtime_data_cut_off_in_days(plan, query)
    end
  end
end
