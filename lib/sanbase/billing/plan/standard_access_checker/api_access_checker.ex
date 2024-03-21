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
    historical_data_in_days: 1 * 365,
    realtime_data_cut_off_in_days: 30
  }

  # Sanbase plans access to API product
  @sanbase_pro_plan_stats @free_plan_stats
  @sanbase_pro_plus_plan_stats Plan.upgrade_plan(@sanbase_pro_plan_stats,
                                 extends: %{
                                   historical_data_in_days: 2 * 365,
                                   realtime_data_cut_off_in_days: 0
                                 }
                               )
  @sanbase_max_plan_stats Plan.upgrade_plan(@sanbase_pro_plan_stats,
                            extends: %{
                              historical_data_in_days: 2 * 365,
                              realtime_data_cut_off_in_days: 0
                            }
                          )

  # API plans access to API product
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
                             extends: %{
                               historical_data_in_days: 2 * 365,
                               realtime_data_cut_off_in_days: 0
                             }
                           )
  # no limit
  @business_max_plan_stats Plan.upgrade_plan(@business_pro_plan_stats,
                             extends: %{historical_data_in_days: nil}
                           )

  @custom_plan_stats Plan.upgrade_plan(@business_max_plan_stats, extends: %{})

  def historical_data_in_days(subscription_product, plan) do
    case subscription_product do
      nil -> historical_data_in_days_api(plan)
      "SANAPI" -> historical_data_in_days_api(plan)
      "SANBASE" -> historical_data_in_days_sanbase(plan)
    end
  end

  def historical_data_in_days_api(plan) do
    case plan do
      "FREE" -> @free_plan_stats[:historical_data_in_days]
      "BASIC" -> @basic_plan_stats[:historical_data_in_days]
      "PRO" -> @pro_plan_stats[:historical_data_in_days]
      "PRO_PLUS" -> @sanbase_pro_plus_plan_stats[:historical_data_in_days]
      "BUSINESS_PRO" -> @business_pro_plan_stats[:historical_data_in_days]
      "BUSINESS_MAX" -> @business_max_plan_stats[:historical_data_in_days]
      "CUSTOM" -> @custom_plan_stats[:historical_data_in_days]
    end
  end

  def historical_data_in_days_sanbase(plan) do
    case plan do
      "BASIC" -> @free_plan_stats[:historical_data_in_days]
      "PRO" -> @free_plan_stats[:historical_data_in_days]
      "PRO_PLUS" -> @sanbase_pro_plus_plan_stats[:historical_data_in_days]
      "MAX" -> @sanbase_max_plan_stats[:historical_data_in_days]
    end
  end

  def realtime_data_cut_off_in_days(subscription_product, plan) do
    case subscription_product do
      nil -> realtime_data_cut_off_in_days_api(plan)
      "SANAPI" -> realtime_data_cut_off_in_days_api(plan)
      "SANBASE" -> realtime_data_cut_off_in_days_sanbase(plan)
    end
  end

  def realtime_data_cut_off_in_days_api(plan) do
    case plan do
      "FREE" -> @free_plan_stats[:realtime_data_cut_off_in_days]
      "BASIC" -> @basic_plan_stats[:realtime_data_cut_off_in_days]
      "PRO" -> @pro_plan_stats[:realtime_data_cut_off_in_days]
      "PRO_PLUS" -> @sanbase_pro_plus_plan_stats[:historical_data_in_days]
      "BUSINESS_PRO" -> @business_pro_plan_stats[:realtime_data_cut_off_in_days]
      "BUSINESS_MAX" -> @business_max_plan_stats[:realtime_data_cut_off_in_days]
      "CUSTOM" -> @custom_plan_stats[:realtime_data_cut_off_in_days]
    end
  end

  def realtime_data_cut_off_in_days_sanbase(plan) do
    case plan do
      "BASIC" -> @free_plan_stats[:realtime_data_cut_off_in_days]
      "PRO" -> @sanbase_pro_plan_stats[:realtime_data_cut_off_in_days]
      "PRO_PLUS" -> @sanbase_pro_plus_plan_stats[:realtime_data_cut_off_in_days]
      "MAX" -> @sanbase_max_plan_stats[:realtime_data_cut_off_in_days]
    end
  end
end
