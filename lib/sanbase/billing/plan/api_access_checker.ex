defmodule Sanbase.Billing.Plan.ApiAccessChecker do
  alias Sanbase.Billing.Plan.AccessChecker.Helper
  alias Sanbase.Billing.Plan.CustomAccess

  @custom_access_queries_stats CustomAccess.get()
  @custom_access_queries @custom_access_queries_stats |> Map.keys() |> Enum.sort()

  def mutations_mapset(), do: Helper.mutations_mapset()

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

  def all_metrics(), do: @premium_metrics

  def free(), do: @free_plan_stats
  def essential(), do: @basic_plan_stats
  def pro(), do: @pro_plan_stats
  def premium(), do: @premium_plan_stats
  def custom(), do: @custom_plan_stats

  def historical_data_in_days(plan, query) when query in @custom_access_queries do
    Map.get(@custom_access_queries_stats, query)
    |> Map.get(:plan_access)
    |> Map.get(plan, %{})
    |> Map.get(:historical_data_in_days)
  end

  def historical_data_in_days(plan, _query) do
    case plan do
      :free -> @free_plan_stats[:historical_data_in_days]
      :basic -> @basic_plan_stats[:historical_data_in_days]
      :pro -> @pro_plan_stats[:historical_data_in_days]
      :premium -> @premium_plan_stats[:historical_data_in_days]
      :custom -> @premium_plan_stats[:historical_data_in_days]
    end
  end

  def realtime_data_cut_off_in_days(plan, query) when query in @custom_access_queries do
    Map.get(@custom_access_queries_stats, query)
    |> Map.get(:plan_access)
    |> Map.get(plan, %{})
    |> Map.get(:realtime_data_cut_off_in_days)
  end

  def realtime_data_cut_off_in_days(plan, _query) do
    case plan do
      :free -> @free_plan_stats[:realtime_data_cut_off_in_days]
      :basic -> @basic_plan_stats[:realtime_data_cut_off_in_days]
      :pro -> @pro_plan_stats[:realtime_data_cut_off_in_days]
      :premium -> @premium_plan_stats[:realtime_data_cut_off_in_days]
      :custom -> @premium_plan_stats[:realtime_data_cut_off_in_days]
    end
  end
end
