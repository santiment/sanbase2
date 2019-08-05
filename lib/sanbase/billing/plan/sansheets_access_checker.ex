defmodule Sanbase.Billing.Plan.SansheetsAccessChecker do
  @moduledoc ~s"""
  Implement the restrictions for the SANSheets product
  """

  @free_plan_stats %{
    historical_data_in_days: 3 * 30,
    realtime_data_cut_off_in_days: 1
  }

  @basic_plan_stats %{
    historical_data_in_days: 6 * 30,
    realtime_data_cut_off_in_days: 0
  }

  @pro_plan_stats %{
    historical_data_in_days: 12 * 30,
    realtime_data_cut_off_in_days: 0
  }

  @enterprise_plan_stats %{
    realtime_data_cut_off_in_days: 0
  }

  def free(), do: @free_plan_stats
  def basic(), do: @basic_plan_stats
  def pro(), do: @pro_plan_stats
  def enterprise(), do: @enterprise_plan_stats

  def historical_data_in_days(plan, _query) do
    case plan do
      :free -> @free_plan_stats[:historical_data_in_days]
      :basic -> @basic_plan_stats[:historical_data_in_days]
      :pro -> @pro_plan_stats[:historical_data_in_days]
      :enterprise -> @enterprise_plan_stats[:historical_data_in_days]
    end
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
