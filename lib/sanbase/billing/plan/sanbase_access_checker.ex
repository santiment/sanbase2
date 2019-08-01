defmodule Sanbase.Billing.Plan.SanbaseAccessChecker do
  alias Sanbase.Billing.Plan.AccessChecker
  alias Sanbase.Billing.Plan.CustomAccess

  @custom_access_queries_stats CustomAccess.get()
  @custom_access_queries @custom_access_queries_stats |> Map.keys() |> Enum.sort()

  @all_metrics AccessChecker.all_metrics()

  @free_plan_stats %{
    historical_data_in_days: 2 * 365,
    realtime_data_cut_off_in_days: 30,
    metrics: @all_metrics,
    signals_limit: 10,
    external_data_providers: false,
    sangraphs_access: false
  }

  @basic_plan_stats %{
    historical_data_in_days: 2 * 365,
    realtime_data_cut_off_in_days: 7,
    metrics: @all_metrics,
    signals_limit: 10,
    external_data_providers: false,
    sangraphs_access: true
  }

  @pro_plan_stats %{
    historical_data_in_days: 3 * 365,
    realtime_data_cut_off_in_days: 0,
    metrics: @all_metrics,
    external_data_providers: true,
    sangraphs_access: true
  }

  @enterprise_plan_stats @pro_plan_stats

  def free(), do: @free_plan_stats
  def basic(), do: @basic_plan_stats
  def pro(), do: @pro_plan_stats
  def enterprise(), do: @enterprise_plan_stats

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
      :enterprise -> @enterprise_plan_stats[:historical_data_in_days]
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
      :enterprise -> @enterprise_plan_stats[:realtime_data_cut_off_in_days]
    end
  end
end
