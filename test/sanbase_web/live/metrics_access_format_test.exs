defmodule SanbaseWeb.MetricsAccessFormatTest do
  use ExUnit.Case, async: true

  import SanbaseWeb.MetricsAccessFormat

  @today ~D[2026-11-26]

  describe "history/3" do
    test "full history" do
      assert history(nil, :relative, @today) == "Full history"
      assert history(nil, :exact, @today) == "Full history"
    end

    test "relative" do
      assert history(730, :relative, @today) == "Last 2 years"
      assert history(365, :relative, @today) == "Last year"
      assert history(1095, :relative, @today) == "Last 3 years"
      assert history(90, :relative, @today) == "Last 90 days"
      assert history(400, :relative, @today) == "Last 400 days"
    end

    test "exact" do
      assert history(730, :exact, @today) == "Since 2024-11-26"
    end
  end

  describe "lag/3" do
    test "realtime" do
      assert lag(nil, :relative, @today) == "Realtime"
      assert lag(nil, :exact, @today) == "Realtime"
    end

    test "relative and exact" do
      assert lag(30, :relative, @today) == "30-day delay"
      assert lag(30, :exact, @today) == "Until 2026-10-27"
    end
  end

  describe "locked/1" do
    test "plan labels come from plans/0" do
      assert locked("sanbase_max") == "Requires Sanbase Max"
      assert locked("business_pro") == "Requires Business Pro"
    end

    test "nil means custom plan only" do
      assert locked(nil) == "Custom plan only"
    end

    test "unknown plan key raises" do
      assert_raise ArgumentError, fn -> locked("bogus") end
    end
  end
end
