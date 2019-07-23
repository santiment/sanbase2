defmodule Sanbase.Pricing.Plan.AccessChecker do
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

  Additionally, this module will arise a compile-time warning if there is a
  query without a subscription plan defined
  """

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

  # Emit a compile time warning if there is any query without subscription plan
  case Helper.queries_without_subsciption_plan() do
    [] ->
      :ok

    queries ->
      IO.warn("""
      There are GraphQL queries defined without specifying their subscription plan.
      Subscription plan belonging is marked by the `meta` field inside the query
      definition. Example: `meta(subscription: :pro)`

      Queries without subscription plan: #{inspect(queries)}
      """)
  end

  # Below are defined lists and sets (for fast member check) of all metrics
  # available in a given plan. Each next plan contains all the metrics from theh
  # lower plans plus some additional metrics

  @free_metrics Helper.get_metrics_with_subscription_plan(:free)
  @free_metrics_mapset MapSet.new(@free_metrics)

  @basic_metrics @free_metrics ++ Helper.get_metrics_with_subscription_plan(:basic)
  @basic_metrics_mapset MapSet.new(@basic_metrics)

  @pro_metrics @basic_metrics ++ Helper.get_metrics_with_subscription_plan(:pro)
  @pro_metrics_mapset MapSet.new(@pro_metrics)

  @premium_metrics @pro_metrics ++ Helper.get_metrics_with_subscription_plan(:premium)
  @premium_metrics_mapset MapSet.new(@premium_metrics)

  @free_plan_stats %{
    api_calls_minute: 10,
    api_calls_month: 1000,
    historical_data_in_days: 3 * 30,
    realtime_data_cut_off_in_days: 1,
    metrics: @free_metrics
  }

  @basic_plan_stats %{
    api_calls_minute: 60,
    api_calls_month: 10_000,
    historical_data_in_days: 6 * 30,
    metrics: @basic_metrics
  }

  @pro_plan_stats %{
    api_calls_minute: 120,
    api_calls_month: 150_000,
    historical_data_in_days: 18 * 30,
    metrics: @pro_metrics
  }

  @premium_plan_stats %{
    api_calls_minute: 180,
    api_calls_month: 500_000,
    metrics: @premium_metrics
  }

  @custom_plan_stats %{
    metrics: @premium_plan_stats
  }

  def free(), do: @free_plan_stats
  def essential(), do: @basic_plan_stats
  def pro(), do: @pro_plan_stats
  def premium(), do: @premium_plan_stats
  def custom(), do: @custom_plan_stats

  def mutations_mapset() do
    Helper.mutations_mapset()
  end

  def historical_data_in_days(plan) do
    case plan do
      :free -> @free_plan_stats[:historical_data_in_days]
      :basic -> @basic_plan_stats[:historical_data_in_days]
      :pro -> @pro_plan_stats[:historical_data_in_days]
      :premium -> @premium_plan_stats[:historical_data_in_days]
      :custom -> @premium_plan_stats[:historical_data_in_days]
    end
  end

  def realtime_data_cut_off_in_days(plan) do
    case plan do
      :free -> @free_plan_stats[:realtime_data_cut_off_in_days] || 0
      :basic -> @basic_plan_stats[:realtime_data_cut_off_in_days] || 0
      :pro -> @pro_plan_stats[:realtime_data_cut_off_in_days] || 0
      :premium -> @premium_plan_stats[:realtime_data_cut_off_in_days] || 0
      :custom -> @premium_plan_stats[:realtime_data_cut_off_in_days] || 0
    end
  end

  @doc ~s"""
  Check if a query full access is given only to users with a plan higher than free.
  A query can be restricted but still accessible by not-paid users or users with
  lower plans. In this case historical and/or realtime data access can be cut off
  """
  def is_restricted?(query) do
    not (query in @free_metrics_mapset)
  end

  @doc ~s"""
  Check if a query access is given only to users with an advanced plan
  (pro or higher). No access is given to users with lower plans
  """
  def needs_advanced_plan?(query) when is_atom(query) do
    query in @premium_metrics_mapset and not (query in @basic_metrics_mapset)
  end

  @doc ~s"""
  Return the atom name of the lowest plan that gives access to a metric
  """
  def lowest_plan_with_metric(query) do
    cond do
      query in @free_metrics_mapset -> :free
      query in @basic_metrics_mapset -> :basic
      query in @pro_metrics_mapset -> :pro
      query in @premium_metrics_mapset -> :premium
      true -> nil
    end
  end

  @doc ~s"""
  Check if a plan (defined as its atom name) has access to a query
  """
  def plan_has_access?(plan, query) do
    case plan do
      :free -> query in @free_metrics_mapset
      :basic -> query in @basic_metrics_mapset
      :pro -> query in @pro_metrics_mapset
      :premium -> query in @premium_metrics_mapset
      :custom -> query in @premium_metrics_mapset
    end
  end
end
