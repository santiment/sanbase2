defmodule Sanbase.Pricing.Plan.AccessSeed do
  @moduledoc """
  Module that holds the access control structure of the subscription plans.
  """

  defmodule Helper do
    require SanbaseWeb.Graphql.Schema

    @query_type Absinthe.Schema.lookup_type(SanbaseWeb.Graphql.Schema, :query)
    @fields @query_type.fields |> Map.keys()
    def get_metrics_with_subscription_plan(plan) do
      Enum.filter(@fields, fn f ->
        Map.get(@query_type.fields, f) |> Absinthe.Type.meta(:subscription) == plan
      end)
    end
  end

  @free_metrics Helper.get_metrics_with_subscription_plan(:free)
  @free_metrics_mapset MapSet.new(@free_metrics)

  @basic_metrics @free_metrics ++ Helper.get_metrics_with_subscription_plan(:basic)
  @basic_metrics_mapset MapSet.new(@basic_metrics)

  @pro_metrics @basic_metrics ++ Helper.get_metrics_with_subscription_plan(:pro)
  @pro_metrics_mapset MapSet.new(@pro_metrics)

  @premium_metrics @pro_metrics ++ Helper.get_metrics_with_subscription_plan(:premium)
  @premium_metrics_mapset MapSet.new(@premium_metrics)
  @all_restricted @premium_metrics -- @free_metrics
  @all_restricted MapSet.new(@all_restricted)

  @free_plan_stats %{
    api_calls_minute: 10,
    api_calls_month: 1000,
    historical_data_in_days: 3 * 30,
    realtime_data_cut_off_in_days: 1,
    metrics: @free_metrics
  }

  @basic_plan_stats %{
    api_calls_minute: 60,
    api_calls_month: 10000,
    historical_data_in_days: 6 * 30,
    realtime_data_cut_off_in_days: 0,
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

  def standart_metrics(), do: @free_metrics
  def advanced_metrics(), do: @basic_metrics
  def all_restricted_metrics(), do: @all_restricted

  def is_restricted?(query) do
    query in @all_restricted
  end

  def needs_advanced_plan?(query) when is_atom(query) do
    query in @premium_metrics_mapset and not (query in @basic_metrics_mapset)
  end

  def needs_advanced_plan?(query) when is_binary(query) do
    String.to_existing_atom(query) in @premium_metrics_mapset and
      not (query in @basic_metrics_mapset)
  end

  def lowest_plan_with_metric(query) do
    cond do
      query in @free_metrics_mapset -> :free
      query in @basic_metrics_mapset -> :basic
      query in @pro_metrics_mapset -> :pro
      query in @premium_metrics_mapset -> :premium
      true -> nil
    end
  end

  def plan_has_access?(plan, query) do
    case plan do
      :free -> query in @free_metrics_mapset
      :basic -> query in @basic_metrics_mapset
      :pro -> query in @pro_metrics_mapset
      :premium -> query in @premium_metrics_mapset
      _ -> false
    end
  end
end
