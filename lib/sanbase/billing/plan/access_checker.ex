defmodule Sanbase.Billing.Plan.AccessChecker do
  @moduledoc """
  Module that contains functions for determining access based on the subscription
  plan.

  Adding new queries or updating the subscription plan does not require this
  module to be changed.

  The subscription plan needed for a given query is given in the query definition
    ```
    field :network_growth, list_of(:network_growth) do
        meta(subscription: :basic)
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
    SanbaseAccessChecker
  }

  defmodule Helper do
    @moduledoc ~s"""
    Contains a single function `get_metrics_with_subscription_plan/1` that examines
    the Absinthe's compile-time build schema.

    It is a different module because functions from the module where a module
    attribute is defined cannot be used
    """
    require SanbaseWeb.Graphql.Schema

    @mutation_type Absinthe.Schema.lookup_type(SanbaseWeb.Graphql.Schema, :mutation)
    @mutations_mapset MapSet.new(@mutation_type.fields |> Map.keys())

    @query_type Absinthe.Schema.lookup_type(SanbaseWeb.Graphql.Schema, :query)
    @fields @query_type.fields |> Map.keys()
    def get_metrics_with_subscription_plan(plan) do
      Enum.filter(@fields, fn f ->
        Map.get(@query_type.fields, f) |> Absinthe.Type.meta(:subscription) == plan
      end)
    end

    def queries_without_subsciption_plan() do
      get_metrics_with_subscription_plan(nil) -- [:__typename, :__type, :__schema]
    end

    def mutations_mapset() do
      @mutations_mapset
    end
  end

  # Raise an error if there is any query without subscription plan
  case Helper.queries_without_subsciption_plan() do
    [] ->
      :ok

    queries ->
      require Sanbase.Break, as: Break

      Break.break("""
      There are GraphQL queries defined without specifying their subscription plan.
      Subscription plan belonging is marked by the `meta` field inside the query
      definition. Example: `meta(subscription: :pro)`

      Queries without subscription plan: #{inspect(queries)}
      """)
  end

  @custom_access_queries_stats CustomAccess.get()
  @custom_access_queries @custom_access_queries_stats |> Map.keys() |> Enum.sort()

  # Raise an error if there are queries with custom access logic
  # but the meta field `subscription` is not correct
  custom_access_meta = Helper.get_metrics_with_subscription_plan(:custom_access) |> Enum.sort()

  if @custom_access_queries != custom_access_meta do
    require Sanbase.Break, as: Break

    Break.break("""
    The list of GraphQL queries with special access defined in the CustomAccess
    module and with subscription meta field `:custom_access` is not the same.

    Queries defined in the CustomAccess module but do not have the `:custom_access`
    meta field: #{inspect(@custom_access_queries -- custom_access_meta)}.

    Queries defined with the `:custom_access` meta field but not present in the
    CustomAccess module: #{inspect(custom_access_meta -- @custom_access_queries)}.
    """)
  end

  @free_metrics Helper.get_metrics_with_subscription_plan(:free)
  @free_metrics_mapset MapSet.new(@free_metrics)
  def free_metrics_mapset(), do: @free_metrics_mapset

  @basic_metrics @free_metrics ++ Helper.get_metrics_with_subscription_plan(:basic)
  @basic_metrics_mapset MapSet.new(@basic_metrics)
  def basic_metrics_mapset(), do: @basic_metrics_mapset

  @pro_metrics @basic_metrics ++ Helper.get_metrics_with_subscription_plan(:pro)
  @pro_metrics_mapset MapSet.new(@pro_metrics)
  def pro_metrics_mapset(), do: @pro_metrics_mapset

  @premium_metrics @pro_metrics ++ Helper.get_metrics_with_subscription_plan(:premium)
  @premium_metrics_mapset MapSet.new(@premium_metrics)
  def premium_metrics_mapset(), do: @premium_metrics_mapset

  def all_metrics, do: @premium_metrics

  @doc ~s"""
  Check if a query full access is given only to users with a plan higher than free.
  A query can be restricted but still accessible by not-paid users or users with
  lower plans. In this case historical and/or realtime data access can be cut off
  """
  def is_restricted?(query) when query in @custom_access_queries, do: true
  def is_restricted?(query), do: not (query in @free_metrics_mapset)

  def custom_access_queries_stats, do: @custom_access_queries_stats
  def custom_access_queries, do: @custom_access_queries

  @product_to_access_module [
    {Product.product_api(), ApiAccessChecker},
    {Product.product_sanbase(), SanbaseAccessChecker},
    {Product.product_sheets(), SanbaseAccessChecker},
    {Product.product_sangraphs(), SanbaseAccessChecker}
  ]

  for {product, module} <- @product_to_access_module do
    def historical_data_in_days(plan, query, unquote(product)) do
      unquote(module).historical_data_in_days(plan, query)
    end

    def realtime_data_cut_off_in_days(plan, query, unquote(product)) do
      unquote(module).realtime_data_cut_off_in_days(plan, query)
    end
  end
end
