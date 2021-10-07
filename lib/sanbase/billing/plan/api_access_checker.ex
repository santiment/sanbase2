defmodule Sanbase.Billing.Plan.ApiAccessChecker do
  @moduledoc ~s"""
  Implement the restrictions for the API product
  """

  # Below are defined lists and sets (for fast member check) of all metrics
  # available in a given plan. Each next plan contains all the metrics from theh
  # lower plans plus some additional metrics

  @doc documentation_ref: "# DOCS access-plans/index.md"

  @free_plan_stats %{
    api_calls_month: 1000,
    historical_data_in_days: 2 * 365,
    realtime_data_cut_off_in_days: 30
  }

  @basic_plan_stats %{
    api_calls_month: 100_000,
    historical_data_in_days: 2 * 365
  }

  @pro_plan_stats %{
    api_calls_month: 300_000
  }

  @premium_plan_stats %{
    api_calls_month: 500_000
  }

  @custom_plan_stats @premium_plan_stats

  def historical_data_in_days(plan, _query) do
    case plan do
      :free -> @free_plan_stats[:historical_data_in_days]
      :basic -> @basic_plan_stats[:historical_data_in_days]
      :pro -> @pro_plan_stats[:historical_data_in_days]
      :premium -> @premium_plan_stats[:historical_data_in_days]
      :custom -> @custom_plan_stats[:historical_data_in_days]
    end
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
