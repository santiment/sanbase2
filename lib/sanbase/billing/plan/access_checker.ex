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

  @doc documentation_ref: "# DOCS access-plans/index.md"

  @type query_or_metric :: {:metric, String.t()} | {:query, atom()}

  alias Sanbase.Billing.{Plan, Product, Subscription, GraphqlSchema}
  alias Sanbase.Billing.Plan.{CustomAccess, ApiAccessChecker, SanbaseAccessChecker}

  # Raise an error if there is any query without subscription plan
  case GraphqlSchema.get_all_without_access_level() do
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

  @extension_metrics GraphqlSchema.get_all_with_access_level(:extension)
  def extension_metrics(), do: @extension_metrics

  @free_metrics GraphqlSchema.get_all_with_access_level(:free)
  @free_metrics_mapset MapSet.new(@free_metrics)
  def free_metrics_mapset(), do: @free_metrics_mapset

  @restricted_metrics GraphqlSchema.get_all_with_access_level(:restricted)
  @restricted_metrics_mapset MapSet.new(@restricted_metrics)
  def restricted_metrics_mapset(), do: @restricted_metrics_mapset

  @all_metrics @free_metrics ++ @restricted_metrics
  def all_metrics, do: @all_metrics

  @custom_access_queries_stats CustomAccess.get()
  @custom_access_queries @custom_access_queries_stats |> Map.keys() |> Enum.sort()
  @custom_access_queries_mapset MapSet.new(@custom_access_queries)

  @free_subscription Subscription.free_subscription()

  # Raise an error if there are queries with custom access logic that are marked
  # as free. If there are such queries the access restriction logic will never
  # be applied

  free_and_custom_intersection =
    MapSet.intersection(@custom_access_queries_mapset, @free_metrics_mapset)

  case Enum.empty?(free_and_custom_intersection) do
    true ->
      :ok

    false ->
      require Sanbase.Break, as: Break

      Break.break("""
      There are queries with access level `:free` that are defined in the
      CustomAccess module. These queries custom access logic will never be
      executed.

      Queries defined in the CustomAccess module but do not have the `:restricted`
      access level field: #{inspect(free_and_custom_intersection |> Enum.to_list())}
      """)
  end

  @doc ~s"""
  Check if a query full access is given only to users with a plan higher than free.
  A query can be restricted but still accessible by not-paid users or users with
  lower plans. In this case historical and/or realtime data access can be cut off
  """
  @spec is_restricted?(query_or_metric) :: boolean()
  def is_restricted?(query_or_metric), do: query_or_metric not in @free_metrics_mapset

  @spec plan_has_access?(plan_name, query_or_metric) :: boolean() when plan_name: atom()
  def plan_has_access?(_plan, _query_or_metric) do
    true
  end

  def custom_access_queries_stats(), do: @custom_access_queries_stats
  def custom_access_queries(), do: @custom_access_queries

  @product_to_access_module [
    {Product.product_api(), ApiAccessChecker},
    {Product.product_sanbase(), SanbaseAccessChecker}
  ]

  @spec historical_data_in_days(%Plan{}, query_or_metric(), non_neg_integer()) ::
          non_neg_integer() | nil
  def historical_data_in_days(plan, query_or_metric, _product_id)
      when query_or_metric in @custom_access_queries do
    Map.get(@custom_access_queries_stats, query_or_metric)
    |> get_in([:plan_access, plan, :historical_data_in_days])
  end

  for {product_id, module} <- @product_to_access_module do
    def historical_data_in_days(plan, query_or_metric, unquote(product_id)) do
      unquote(module).historical_data_in_days(plan, query_or_metric)
    end
  end

  @spec realtime_data_cut_off_in_days(%Plan{}, query_or_metric(), non_neg_integer()) ::
          non_neg_integer() | nil
  def realtime_data_cut_off_in_days(plan, query_or_metric, _product_id)
      when query_or_metric in @custom_access_queries do
    Map.get(@custom_access_queries_stats, query_or_metric)
    |> get_in([:plan_access, plan, :realtime_data_cut_off_in_days])
  end

  for {product_id, module} <- @product_to_access_module do
    def realtime_data_cut_off_in_days(plan, query_or_metric, unquote(product_id)) do
      unquote(module).realtime_data_cut_off_in_days(plan, query_or_metric)
    end
  end

  def user_can_create_signal?(user, subscription) do
    subscription = subscription || @free_subscription

    cond do
      # If user has API subscription - he has unlimited signals
      subscription.plan.product_id == Product.product_api() -> true
      SanbaseAccessChecker.signals_limits_not_reached?(user, subscription) -> true
      true -> false
    end
  end

  def signals_limits_upgrade_message(), do: SanbaseAccessChecker.signals_limits_upgrade_message()
end
