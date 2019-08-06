defmodule Sanbase.Billing.Plan.ApiAccessChecker do
  @moduledoc ~s"""
  Implement the restrictions for the API product
  """

  alias Sanbase.Billing.Plan.CustomAccess

  @custom_access_queries_stats CustomAccess.get()
  @custom_access_queries @custom_access_queries_stats |> Map.keys() |> Enum.sort()

  # Below are defined lists and sets (for fast member check) of all metrics
  # available in a given plan. Each next plan contains all the metrics from theh
  # lower plans plus some additional metrics

  @free_plan_stats %{
    api_calls_minute: 10,
    api_calls_month: 1000,
    historical_data_in_days: 3 * 30,
    realtime_data_cut_off_in_days: 1
  }

  @basic_plan_stats %{
    api_calls_minute: 60,
    api_calls_month: 10_000,
    historical_data_in_days: 6 * 30
  }

  @pro_plan_stats %{
    api_calls_minute: 120,
    api_calls_month: 150_000,
    historical_data_in_days: 18 * 30
  }

  @premium_plan_stats %{
    api_calls_minute: 180,
    api_calls_month: 500_000
  }

  @enterprise_plan_stats @premium_plan_stats

  def historical_data_in_days(plan, query) when query in @custom_access_queries do
    Map.get(@custom_access_queries_stats, query)
    |> get_in([:plan_access, plan, :historical_data_in_days])
  end

  def historical_data_in_days(plan, _query) do
    case plan do
      :free -> @free_plan_stats[:historical_data_in_days]
      :basic -> @basic_plan_stats[:historical_data_in_days]
      :pro -> @pro_plan_stats[:historical_data_in_days]
      :premium -> @premium_plan_stats[:historical_data_in_days]
      :enterprise -> @premium_plan_stats[:historical_data_in_days]
    end
  end

  def realtime_data_cut_off_in_days(plan, query) when query in @custom_access_queries do
    Map.get(@custom_access_queries_stats, query)
    |> get_in([:plan_access, plan, :realtime_data_cut_off_in_days])
  end

  def realtime_data_cut_off_in_days(plan, _query) do
    case plan do
      :free -> @free_plan_stats[:realtime_data_cut_off_in_days]
      :basic -> @basic_plan_stats[:realtime_data_cut_off_in_days]
      :pro -> @pro_plan_stats[:realtime_data_cut_off_in_days]
      :premium -> @premium_plan_stats[:realtime_data_cut_off_in_days]
      :enterprise -> @premium_plan_stats[:realtime_data_cut_off_in_days]
    end
  end
end
