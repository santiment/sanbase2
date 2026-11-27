defmodule Sanbase.Billing.Plan.RestrictionsSubscriptionProductTest do
  use Sanbase.DataCase, async: true

  alias Sanbase.Billing.Plan.ApiAccessChecker
  alias Sanbase.Billing.Plan.Restrictions

  test "FREE with a SANBASE subscription product answers like API FREE" do
    assert ApiAccessChecker.historical_data_in_days("SANBASE", "FREE") == 365
    assert ApiAccessChecker.realtime_data_cut_off_in_days("SANBASE", "FREE") == 30
  end

  test "every plan name a SANBASE subscription can carry has a clause" do
    for plan <- ["FREE", "BASIC", "PRO", "PRO_PLUS", "MAX"] do
      historical = ApiAccessChecker.historical_data_in_days("SANBASE", plan)
      realtime = ApiAccessChecker.realtime_data_cut_off_in_days("SANBASE", plan)

      assert is_integer(historical) or is_nil(historical)
      assert is_integer(realtime) or is_nil(realtime)
    end
  end

  test "get_all keeps today's answer when no subscription product is given" do
    r = Restrictions.get_all("PRO", "SANAPI", :metric) |> Enum.find(&(&1.name == "mvrv_usd"))
    assert r.restricted_from == nil and r.restricted_to == nil
  end

  test "Sanbase PRO via API: 1y history and 30-day lag" do
    r =
      Restrictions.get_all("PRO", "SANAPI", :metric, nil, nil, "SANBASE")
      |> Enum.find(&(&1.name == "mvrv_usd"))

    assert_in_delta DateTime.diff(DateTime.utc_now(), r.restricted_from, :day), 365, 1
    assert_in_delta DateTime.diff(DateTime.utc_now(), r.restricted_to, :day), 30, 1
  end
end
