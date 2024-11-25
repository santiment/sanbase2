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

  @type query_or_argument :: {:metric, String.t()} | {:signal, String.t()} | {:query, Atom.t()}
  @type requested_product :: String.t()
  @type subscription_product :: String.t()
  @type product_code :: String.t()
  @type plan_name :: String.t()

  alias Sanbase.Billing.ApiInfo

  alias Sanbase.Billing.Plan.{
    ApiAccessChecker,
    SanbaseAccessChecker
  }

  require Logger

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

  @doc ~s"""
  Check if a query full access is given only to users with a plan higher than free.
  A query can be restricted but still accessible by not-paid users or users with
  lower plans. In this case historical and/or realtime data access can be cut off
  """
  @spec restricted?(query_or_argument) :: boolean()
  def restricted?(query_or_argument),
    do: query_or_argument not in free_query_or_argument_mapset()

  @spec plan_has_access?(query_or_argument, requested_product, plan_name) :: boolean()
  def plan_has_access?(query_or_argument, requested_product, plan_name) do
    case min_plan(requested_product, query_or_argument) do
      "FREE" -> true
      "BASIC" -> plan_name != "FREE"
      "PRO" -> plan_name not in ["FREE", "BASIC"]
      "CUSTOM" -> plan_name == "CUSTOM"
      _ -> true
    end
  end

  @spec min_plan(product_code, query_or_argument) :: plan_name
  def min_plan(product_code, query_or_argument) do
    min_plan_map()[query_or_argument][product_code] || "FREE"
  end

  @spec get_available_metrics_for_plan(plan_name, product_code, Atom.t()) ::
          list(binary())
  def get_available_metrics_for_plan(plan_name, product_code, restriction_type \\ :all)

  def get_available_metrics_for_plan(plan_name, product_code, restriction_type) do
    case restriction_type do
      :free -> free_query_or_argument()
      :restricted -> restricted_query_or_argument()
      :all -> all_query_or_argument()
    end
    |> Stream.filter(&match?({:metric, _}, &1))
    |> Stream.filter(&plan_has_access?(&1, product_code, plan_name))
    |> Enum.map(fn {_, name} -> name end)
  end

  def historical_data_freely_available?(query_or_argument) do
    case query_or_argument do
      {:metric, metric} ->
        Sanbase.Metric.historical_data_freely_available?(metric)

      {:signal, signal} ->
        Sanbase.Signal.historical_data_freely_available?(signal)

      {:query, _} ->
        false
    end
  end

  def realtime_data_freely_available?(query_or_argument) do
    case query_or_argument do
      {:metric, metric} ->
        Sanbase.Metric.realtime_data_freely_available?(metric)

      {:signal, signal} ->
        Sanbase.Signal.realtime_data_freely_available?(signal)

      {:query, _} ->
        false
    end
  end

  @product_to_access_module %{
    "SANAPI" => ApiAccessChecker,
    "SANBASE" => SanbaseAccessChecker
  }

  @doc """
  If the result from this function is nil, then no restrictions are applied.
  Respectively the `restrictedFrom` field has a value of nil as well.
  """
  @spec historical_data_in_days(
          query_or_argument(),
          requested_product,
          subscription_product,
          plan_name
        ) ::
          non_neg_integer() | nil
  def historical_data_in_days(
        query_or_argument,
        requested_product,
        subscription_product,
        plan_name
      ) do
    if historical_data_freely_available?(query_or_argument) do
      # nil represents no restrictions
      nil
    else
      module = @product_to_access_module[requested_product]
      apply(module, :historical_data_in_days, [subscription_product, plan_name])
    end
  end

  @doc """
  If the result from this function is nil, then no restrictions are applied.
  Respectively the `restrictedTo` field has a value of nil as well.
  """
  @spec realtime_data_cut_off_in_days(
          query_or_argument(),
          requested_product,
          subscription_product,
          plan_name
        ) ::
          non_neg_integer() | nil

  def realtime_data_cut_off_in_days(
        query_or_argument,
        requested_product,
        subscription_product,
        plan_name
      ) do
    if realtime_data_freely_available?(query_or_argument) do
      # nil represents no restrictions
      nil
    else
      module = @product_to_access_module[requested_product]
      apply(module, :realtime_data_cut_off_in_days, [subscription_product, plan_name])
    end
  end

  @functions [
    {:query_or_argument, [:free]},
    {:query_or_argument_mapset, [:free]},
    {:query_or_argument, [:restricted]},
    {:query_or_argument, [:all]},
    {:min_plan_map, []}
  ]

  def refresh_stored_terms() do
    Logger.info("Refreshing stored terms in the #{__MODULE__}")

    result =
      for {fun, args} <- @functions do
        data = compute(fun, args)

        if :not_implemented == data,
          do: raise("Function #{fun} is not implemented in module #{__MODULE__}")

        result = :persistent_term.put(key(fun, args), data)
        {{fun, args}, result}
      end

    Enum.all?(result, &match?({_, :ok}, &1))
  end

  # Private functions

  defp free_query_or_argument(), do: get(:query_or_argument, [:free])
  defp free_query_or_argument_mapset(), do: get(:query_or_argument_mapset, [:free])
  defp restricted_query_or_argument(), do: get(:query_or_argument, [:restricted])
  defp all_query_or_argument(), do: get(:query_or_argument, [:all])
  defp min_plan_map(), do: get(:min_plan_map)

  defp get(fun, args \\ []) do
    key = key(fun, args)

    case :persistent_term.get(key, :undefined) do
      :undefined ->
        data = compute(fun, args)
        :persistent_term.put(key, data)
        data

      data ->
        data
    end
  end

  defp key(fun, args), do: {__MODULE__, fun, args}

  defp compute(:query_or_argument, [:all]) do
    ApiInfo.get_all_with_access_level(:free) ++ ApiInfo.get_all_with_access_level(:restricted)
  end

  defp compute(:query_or_argument, [level]) when level in [:free, :restricted] do
    ApiInfo.get_all_with_access_level(level)
  end

  defp compute(:query_or_argument_mapset, [level]) when level in [:free, :restricted, :all] do
    compute(:query_or_argument, [level])
    |> MapSet.new()
  end

  defp compute(:min_plan_map, []) do
    ApiInfo.min_plan_map()
  end
end
