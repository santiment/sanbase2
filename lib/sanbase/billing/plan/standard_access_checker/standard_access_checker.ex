defmodule Sanbase.Billing.Plan.StandardAccessChecker do
  @moduledoc """
  Module that contains functions for determining access based on the subscription
  plan.

  Adding new queries or updating the subscription plan does not require this
  module to be changed.

  The subscription plan needed for a given query is given in the query definition
    ```
    field :network_growth, list_of(:network_growth) do
        meta(access: :restricted, min_plan: [sanapi: "PRO", sanbase: "FREE"])
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

  @type plan_name :: String.t()
  @type product_code :: String.t()
  @type query_or_argument :: {:metric, String.t()} | {:signal, String.t()} | {:query, Atom.t()}

  alias Sanbase.Billing.ApiInfo

  alias Sanbase.Billing.Plan.{
    MVRVAccess,
    ApiAccessChecker,
    SanbaseAccessChecker
  }

  @doc documentation_ref: "# DOCS access-plans/index.md"

  case ApiInfo.get_queries_without_access_level() do
    [] ->
      :ok

    queries ->
      require Sanbase.Break, as: Break

      Break.break("""
      There are GraphQL queries defined without specifying their access level.
      The access level could be either `free` or `restricted`.
      To define an access level, put `meta(access: <level>)` in the field definition.

      Queries without access level: #{inspect(queries)}
      """)
  end

  @free_query_or_argument ApiInfo.get_all_with_access_level(:free)
  @free_query_or_argument_mapset MapSet.new(@free_query_or_argument)

  @restricted_query_or_argument ApiInfo.get_all_with_access_level(:restricted)

  @all_query_or_argument @free_query_or_argument ++ @restricted_query_or_argument

  @custom_access_queries_stats MVRVAccess.get()
  @custom_access_queries @custom_access_queries_stats |> Map.keys() |> Enum.sort()
  @custom_access_queries_mapset MapSet.new(@custom_access_queries)

  @min_plan_map ApiInfo.min_plan_map()

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
      There are queries with access level `FREE` that are defined in the
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
  @spec is_restricted?(plan_name, product_code, query_or_argument) :: boolean()
  def is_restricted?(_plan_name, _product_code, query_or_argument),
    do: query_or_argument not in @free_query_or_argument_mapset

  @spec plan_has_access?(plan_name, product_code, query_or_argument) :: boolean()
  def plan_has_access?(plan_name, product_code, query_or_argument) do
    min_plan(product_code, query_or_argument)

    case min_plan(product_code, query_or_argument) do
      "FREE" -> true
      "BASIC" -> plan_name != "FREE"
      "PRO" -> plan_name not in ["FREE", "BASIC"]
      "PREMIUM" -> plan_name not in ["FREE", "BASIC", "PRO"]
      "CUSTOM" -> plan_name == "CUSTOM"
      _ -> true
    end
  end

  @spec min_plan(product_code, query_or_argument) :: plan_name
  def min_plan(product_code, query_or_argument) do
    @min_plan_map[query_or_argument][product_code] || "FREE"
  end

  @spec get_available_metrics_for_plan(plan_name, product_code, Atom.t()) ::
          list(binary())
  def get_available_metrics_for_plan(plan_name, product_code, restriction_type \\ :all)

  def get_available_metrics_for_plan(plan_name, product_code, restriction_type) do
    case restriction_type do
      :free -> @free_query_or_argument
      :restricted -> @restricted_query_or_argument
      :custom -> @custom_access_queries
      :all -> @all_query_or_argument
    end
    |> Stream.filter(&match?({:metric, _}, &1))
    |> Stream.filter(&plan_has_access?(plan_name, product_code, &1))
    |> Enum.map(fn {_, name} -> name end)
  end

  def is_historical_data_freely_available?(_plan_name, _product_code, query_or_argument) do
    case query_or_argument do
      {:metric, metric} ->
        Sanbase.Metric.is_historical_data_freely_available?(metric)

      {:signal, signal} ->
        Sanbase.Signal.is_historical_data_freely_available?(signal)

      {:query, _} ->
        false
    end
  end

  def is_realtime_data_freely_available?(_plan_name, _product_name, query_or_argument) do
    case query_or_argument do
      {:metric, metric} ->
        Sanbase.Metric.is_realtime_data_freely_available?(metric)

      {:signal, signal} ->
        Sanbase.Signal.is_realtime_data_freely_available?(signal)

      {:query, _} ->
        false
    end
  end

  @product_to_access_module [
    {"SANAPI", ApiAccessChecker},
    {"SANBASE", SanbaseAccessChecker}
  ]

  @doc """
  If the result from this function is nil, then no restrictions are applied.
  Respectively the `restrictedFrom` field has a value of nil as well.
  """
  @spec historical_data_in_days(plan_name, product_code, query_or_argument()) ::
          non_neg_integer() | nil
  def historical_data_in_days(plan_name, product_code, query_or_argument)
      when query_or_argument in @custom_access_queries do
    if not is_historical_data_freely_available?(plan_name, product_code, query_or_argument) do
      Map.get(@custom_access_queries_stats, query_or_argument)
      |> get_in([:plan_access, plan_name, :historical_data_in_days])
    end
  end

  for {product_code, module} <- @product_to_access_module do
    def historical_data_in_days(plan_name, unquote(product_code), query_or_argument) do
      if not is_historical_data_freely_available?(
           plan_name,
           unquote(product_code),
           query_or_argument
         ) do
        # product_code is not needed as these modules are named Api* and Sanbase*
        unquote(module).historical_data_in_days(plan_name, query_or_argument)
      end
    end
  end

  @doc """
  If the result from this function is nil, then no restrictions are applied.
  Respectively the `restrictedTo` field has a value of nil as well.
  """
  @spec realtime_data_cut_off_in_days(plan_name, product_code, query_or_argument()) ::
          non_neg_integer() | nil
  def realtime_data_cut_off_in_days(plan_name, product_code, query_or_argument)
      when query_or_argument in @custom_access_queries do
    if not is_realtime_data_freely_available?(plan_name, product_code, query_or_argument) do
      Map.get(@custom_access_queries_stats, query_or_argument)
      |> get_in([:plan_access, plan_name, :realtime_data_cut_off_in_days])
    end
  end

  for {product_code, module} <- @product_to_access_module do
    def realtime_data_cut_off_in_days(plan_name, unquote(product_code), query_or_argument) do
      if not is_realtime_data_freely_available?(
           plan_name,
           unquote(product_code),
           query_or_argument
         ) do
        # product_code is not needed as these modules are named Api* and Sanbase*
        unquote(module).realtime_data_cut_off_in_days(plan_name, query_or_argument)
      end
    end
  end
end
