defmodule Sanbase.Billing.Plan.ApiAccessChecker do
  @moduledoc ~s"""
  Implement the restrictions for the API product
  """

  # Below are defined lists and sets (for fast member check) of all metrics
  # available in a given plan. Each next plan contains all the metrics from theh
  # lower plans plus some additional metrics

  @doc documentation_ref: "# DOCS access-plans/index.md"

  alias Sanbase.Billing.Plan

  @free_plan_stats %{
    historical_data_in_days: 2 * 365,
    realtime_data_cut_off_in_days: 30
  }

  @basic_plan_stats Plan.upgrade_plan(@free_plan_stats,
                      extends: %{realtime_data_cut_off_in_days: 0}
                    )

  @pro_plan_stats Plan.upgrade_plan(@free_plan_stats,
                    extends: %{
                      realtime_data_cut_off_in_days: 0,
                      # no limit
                      historical_data_in_days: nil
                    }
                  )

  @business_pro_plan_stats Plan.upgrade_plan(@free_plan_stats,
                             extends: %{realtime_data_cut_off_in_days: 0}
                           )
  # no limit
  @business_max_plan_stats Plan.upgrade_plan(@business_pro_plan_stats,
                             extends: %{historical_data_in_days: nil}
                           )

  @custom_plan_stats Plan.upgrade_plan(@business_max_plan_stats, extends: %{})

  def historical_data_in_days(plan, _query) do
    case plan do
      "FREE" -> @free_plan_stats[:historical_data_in_days]
      "BASIC" -> @basic_plan_stats[:historical_data_in_days]
      "PRO" -> @pro_plan_stats[:historical_data_in_days]
      "BUSINESS_PRO" -> @business_pro_plan_stats[:historical_data_in_days]
      "BUSINESS_MAX" -> @business_max_plan_stats[:historical_data_in_days]
      "CUSTOM" -> @custom_plan_stats[:historical_data_in_days]
    end
  end

  def realtime_data_cut_off_in_days(plan, _query) do
    case plan do
      "FREE" -> @free_plan_stats[:realtime_data_cut_off_in_days]
      "BASIC" -> @basic_plan_stats[:realtime_data_cut_off_in_days]
      "PRO" -> @pro_plan_stats[:realtime_data_cut_off_in_days]
      "BUSINESS_PRO" -> @business_pro_plan_stats[:realtime_data_cut_off_in_days]
      "BUSINESS_MAX" -> @business_max_plan_stats[:realtime_data_cut_off_in_days]
      "CUSTOM" -> @custom_plan_stats[:realtime_data_cut_off_in_days]
    end
  end
end
