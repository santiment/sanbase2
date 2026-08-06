defmodule Sanbase.ApiCallLimit.Restrictions do
  @moduledoc ~s"""
  The per-plan call and response-size allowances, keyed by the product-prefixed,
  downcased plan name stored in `api_call_limits.api_calls_limit_plan`.

  ## `sanapi_institutional`

  Its monthly allowance is 50,000 - lower than every other paid SanAPI plan, and
  lower than a single composable package. That is the product's intent, not an
  oversight: Institutional sells breadth of access and a 3-year history window
  rather than volume, and volume is what the packages and their add-ons sell. See
  `docs/composable-api-plans-handover.md` §8 task IN and §9.

  The hour and minute figures are burst limits and are taken from `sanapi_pro`,
  the same numbers a bundle gets. They are deliberately not scaled down in
  proportion to the month: the monthly figure is the constraint being sold, and an
  institutional customer backfilling a dataset should not be throttled harder than
  a package customer while still inside their monthly allowance.
  """

  def call_limits_per_month() do
    %{
      "sanbase_basic" => 1000,
      "sanbase_pro" => 5000,
      "sanbase_pro_plus" => 80_000,
      "sanbase_max" => 80_000,
      "sanapi_free" => 1000,
      "sanapi_basic" => 300_000,
      "sanapi_pro" => 600_000,
      "sanapi_business_pro" => 600_000,
      "sanapi_business_max" => 1_200_000,
      "sanapi_institutional" => 50_000
    }
  end

  def call_limits_per_hour() do
    %{
      "sanbase_basic" => 500,
      "sanbase_pro" => 1000,
      "sanbase_pro_plus" => 4000,
      "sanbase_max" => 4000,
      "sanapi_free" => 500,
      "sanapi_basic" => 20_000,
      "sanapi_pro" => 30_000,
      "sanapi_business_pro" => 30_000,
      "sanapi_business_max" => 60_000,
      "sanapi_institutional" => 30_000
    }
  end

  def call_limits_per_minute() do
    %{
      "sanbase_basic" => 100,
      "sanbase_pro" => 100,
      "sanbase_pro_plus" => 100,
      "sanbase_max" => 100,
      "sanapi_free" => 100,
      "sanapi_basic" => 300,
      "sanapi_pro" => 600,
      "sanapi_business_pro" => 600,
      "sanapi_business_max" => 1200,
      "sanapi_institutional" => 600
    }
  end

  def response_size_limits_mb_per_month() do
    # TODO: After gathering enough statistics of actual usage update these
    # values
    %{
      "sanbase_basic" => 1000,
      "sanbase_pro" => 2000,
      "sanbase_pro_plus" => 12_000,
      "sanbase_max" => 20_000,
      "sanapi_free" => 1000,
      "sanapi_basic" => 20_000,
      "sanapi_pro" => 40_000,
      "sanapi_business_pro" => 50_000,
      "sanapi_business_max" => 100_000,
      "sanapi_institutional" => 50_000
    }
  end
end
