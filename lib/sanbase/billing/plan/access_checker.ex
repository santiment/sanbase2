defmodule Sanbase.Billing.Plan.AccessChecker do
  @moduledoc """
  Module that contains functions for determining access based on the subscription
  plan.

  Adding new queries or updating the subscription plan does not require this
  module to be changed.

  The subscription plan needed for a given query is given in the query definition
    ```
    field :network_growth, list_of(:network_growth) do
        meta(access: :restricted, min_plan: [sanapi: :pro, sanbase: :free])
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

  alias Sanbase.Billing.{Product, Subscription, GraphqlSchema}
  alias Sanbase.Billing.Plan.{CustomAccess, ApiAccessChecker, SanbaseAccessChecker}

  @doc documentation_ref: "# DOCS access-plans/index.md"

  @type query_or_argument :: {:metric, String.t()} | {:signal, String.t()} | {:query, atom()}

  @extension_metrics GraphqlSchema.get_all_with_access_level(:extension)
  def extension_metrics(), do: @extension_metrics

  @free_query_or_argument GraphqlSchema.get_all_with_access_level(:free)
  @free_query_or_argument_mapset MapSet.new(@free_query_or_argument)
  def free_query_or_argument_mapset(), do: @free_query_or_argument_mapset

  @restricted_metrics GraphqlSchema.get_all_with_access_level(:restricted)
  @restricted_metrics_mapset MapSet.new(@restricted_metrics)
  def restricted_metrics_mapset(), do: @restricted_metrics_mapset

  @all_metrics @free_query_or_argument ++ @restricted_metrics
  def all_metrics, do: @all_metrics

  @custom_access_queries_stats CustomAccess.get()
  @custom_access_queries @custom_access_queries_stats |> Map.keys() |> Enum.sort()
  @custom_access_queries_mapset MapSet.new(@custom_access_queries)

  @free_subscription Subscription.free_subscription()

  @min_plan_map GraphqlSchema.min_plan_map()

  # Raise an error if there are queries with custom access logic that are marked
  # as free. If there are such queries the access restriction logic will never
  # be applied

  free_and_custom_intersection =
    MapSet.intersection(@custom_access_queries_mapset, @free_query_or_argument_mapset)

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
  @spec is_restricted?(query_or_argument) :: boolean()
  def is_restricted?(query_or_argument),
    do: query_or_argument not in @free_query_or_argument_mapset

  @spec plan_has_access?(plan, product, query_or_argument) :: boolean()
        when plan: atom(), product: binary()
  def plan_has_access?(plan, product, query_or_argument) do
    case min_plan(product, query_or_argument) do
      :free -> true
      :basic -> plan != :free
      :pro -> plan not in [:free, :basic]
      :premium -> plan not in [:free, :basic, :pro]
      :custom -> plan == :custom
      # extensions plans can be with other plan. They're handled separately
      _ -> true
    end
  end

  @spec min_plan(product, query_or_argument) :: atom() when product: binary()
  def min_plan(product, query_or_argument) do
    @min_plan_map[query_or_argument][product] || :free
  end

  @spec get_available_metrics_for_plan(product, plan, restriction_type) :: list(binary())
        when plan: atom(), product: binary(), restriction_type: atom()
  def get_available_metrics_for_plan(product, plan, restriction_type \\ :all) do
    case restriction_type do
      :free -> @free_query_or_argument
      :restricted -> @restricted_metrics
      :custom -> @custom_access_queries
      :all -> @all_metrics
    end
    |> Stream.filter(&match?({:metric, _}, &1))
    |> Stream.filter(&plan_has_access?(plan, product, &1))
    |> Enum.map(fn {_, name} -> name end)
  end

  def custom_access_queries_stats(), do: @custom_access_queries_stats
  def custom_access_queries(), do: @custom_access_queries

  @product_to_access_module [
    {Product.product_api(), ApiAccessChecker},
    {Product.product_sanbase(), SanbaseAccessChecker}
  ]

  @spec historical_data_in_days(atom(), non_neg_integer(), query_or_argument()) ::
          non_neg_integer() | nil
  def historical_data_in_days(plan, _product_id, query_or_argument)
      when query_or_argument in @custom_access_queries do
    Map.get(@custom_access_queries_stats, query_or_argument)
    |> get_in([:plan_access, plan, :historical_data_in_days])
  end

  for {product_id, module} <- @product_to_access_module do
    def historical_data_in_days(plan, unquote(product_id), query_or_argument) do
      unquote(module).historical_data_in_days(plan, query_or_argument)
    end
  end

  @spec realtime_data_cut_off_in_days(atom(), non_neg_integer(), query_or_argument()) ::
          non_neg_integer() | nil
  def realtime_data_cut_off_in_days(plan, _product_id, query_or_argument)
      when query_or_argument in @custom_access_queries do
    Map.get(@custom_access_queries_stats, query_or_argument)
    |> get_in([:plan_access, plan, :realtime_data_cut_off_in_days])
  end

  for {product_id, module} <- @product_to_access_module do
    def realtime_data_cut_off_in_days(plan, unquote(product_id), query_or_argument) do
      unquote(module).realtime_data_cut_off_in_days(plan, query_or_argument)
    end
  end

  def user_can_create_alert?(user, subscription) do
    subscription = subscription || @free_subscription

    SanbaseAccessChecker.alerts_limits_not_reached?(user, subscription)
  end

  def alerts_limits_upgrade_message(), do: SanbaseAccessChecker.alerts_limits_upgrade_message()
end
