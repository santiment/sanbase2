defmodule Sanbase.Billing.Plan.ApiAccessCheckerTest do
  use ExUnit.Case, async: true

  alias Sanbase.Billing.Plan.ApiAccessChecker

  describe "realtime_data_cut_off_in_days/2" do
    test "PRO_PLUS has no realtime cut-off on either product" do
      assert ApiAccessChecker.realtime_data_cut_off_in_days("SANAPI", "PRO_PLUS") == 0
      assert ApiAccessChecker.realtime_data_cut_off_in_days(nil, "PRO_PLUS") == 0
      assert ApiAccessChecker.realtime_data_cut_off_in_days("SANBASE", "PRO_PLUS") == 0
    end
  end
end
