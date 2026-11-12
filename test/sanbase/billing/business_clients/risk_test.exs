defmodule Sanbase.Billing.BusinessClients.RiskTest do
  use ExUnit.Case, async: true

  alias Sanbase.Billing.BusinessClients.{Risk, Settings}

  @settings Settings.defaults()

  # An established monthly client on a business plan, active most days, steady usage.
  defp facts(attrs) do
    Map.merge(
      %{
        segment: :plan,
        interval: "month",
        tenure_days: 400,
        active_days: {25, 25},
        api_calls: {5_000, 5_000},
        days_to_renewal: 12
      },
      Map.new(attrs)
    )
  end

  defp level(attrs, settings \\ @settings), do: Risk.assess(facts(attrs), settings).level
  defp reasons(attrs), do: Risk.assess(facts(attrs), @settings).reasons

  describe "business plan, monthly" do
    test "an established, active client with steady usage is healthy" do
      assert Risk.assess(facts([]), @settings) == %{level: :healthy, reasons: []}
    end

    test "active on few days is High Risk, on a moderate number At Risk" do
      assert level(active_days: {7, 7}) == :high_risk
      assert level(active_days: {8, 8}) == :at_risk
      assert level(active_days: {15, 15}) == :at_risk
      assert level(active_days: {16, 16}) == :healthy

      assert reasons(active_days: {7, 7}) == ["Active on 7 of the last 30 days"]
      assert reasons(active_days: {0, 0}) == ["No activity in the last 30 days"]
    end

    test "a new client is At Risk, and High Risk when usage also dropped" do
      assert level(tenure_days: 92) == :at_risk
      assert level(tenure_days: 93) == :healthy
      assert reasons(tenure_days: 40) == ["New client (40 days)"]

      assert level(tenure_days: 40, api_calls: {600, 1_000}) == :high_risk

      assert reasons(tenure_days: 40, api_calls: {600, 1_000}) ==
               ["New client (40 days) with usage down 40% (API calls)"]
    end

    test "a usage drop alone is At Risk, whether in API calls or in active days" do
      assert level(api_calls: {700, 1_000}) == :at_risk
      assert level(api_calls: {710, 1_000}) == :healthy
      assert reasons(api_calls: {300, 1_000}) == ["Usage down 70% (API calls)"]

      assert level(active_days: {17, 25}) == :at_risk
      assert reasons(active_days: {17, 25}) == ["Usage down 32% (active days)"]
    end

    test "the larger of the two drops is the one reported" do
      assert reasons(api_calls: {600, 1_000}, active_days: {16, 25}) ==
               ["Usage down 40% (API calls)"]
    end

    test "a previous window too small to compare with is not a drop" do
      assert level(api_calls: {0, 99}) == :healthy
      assert level(active_days: {16, 4}, api_calls: {nil, nil}) == :healthy
    end

    test "unknown API calls still leave the active days to judge by" do
      assert level(api_calls: {nil, nil}) == :healthy
      assert level(api_calls: {nil, nil}, active_days: {3, 20}) == :high_risk
    end

    test "the reasons list every signal, the most severe first" do
      assert reasons(tenure_days: 40, active_days: {5, 5}) ==
               ["Active on 5 of the last 30 days", "New client (40 days)"]
    end
  end

  describe "business email, monthly" do
    test "an established client active on more than a few days is healthy" do
      assert level(segment: :business_email, active_days: {8, 8}) == :healthy
    end

    test "no activity is High Risk" do
      assert Risk.assess(facts(segment: :business_email, active_days: {0, 9}), @settings) ==
               %{level: :high_risk, reasons: ["No activity in the last 30 days"]}
    end

    test "a new client with moderate activity is High Risk, an active one At Risk" do
      new = [segment: :business_email, tenure_days: 30]

      assert level(new ++ [active_days: {15, 0}]) == :high_risk
      assert level(new ++ [active_days: {16, 0}]) == :at_risk

      assert reasons(new ++ [active_days: {15, 0}]) ==
               ["New client (30 days), active on 15 of the last 30 days"]
    end

    test "an established client active on few days is At Risk" do
      assert level(segment: :business_email, active_days: {7, 7}) == :at_risk
      assert level(segment: :business_email, active_days: {1, 1}) == :at_risk
    end

    test "a usage drop does not count for this segment" do
      assert level(segment: :business_email, active_days: {10, 25}, api_calls: {0, 5_000}) ==
               :healthy
    end
  end

  describe "yearly" do
    test "At Risk within the renewal window, healthy before it, whatever the usage" do
      yearly = [interval: "year", active_days: {0, 0}, tenure_days: 10]

      assert level(yearly ++ [days_to_renewal: 91]) == :healthy
      assert level(yearly ++ [days_to_renewal: 90]) == :at_risk
      assert reasons(yearly ++ [days_to_renewal: 45]) == ["Renews in 45 day(s)"]
      assert reasons(yearly ++ [days_to_renewal: 0]) == ["Renews today"]
      assert reasons(yearly ++ [days_to_renewal: -3]) == ["Renewal was due 3 day(s) ago"]
    end

    test "no renewal date and no usage data are both fine" do
      assert level(interval: "year", days_to_renewal: nil, active_days: nil) == :healthy
    end
  end

  test "a monthly client whose usage could not be read is unknown" do
    assert Risk.assess(facts(active_days: nil), @settings) ==
             %{level: :unknown, reasons: ["Usage data is not available"]}
  end

  test "the thresholds come from the settings" do
    settings = %{
      @settings
      | risk_high_active_days: 3,
        risk_low_active_days: 10,
        risk_new_client_days: 30,
        risk_usage_drop_percent: 50,
        risk_renewal_days: 30
    }

    assert level([active_days: {4, 4}], settings) == :at_risk
    assert level([active_days: {11, 11}], settings) == :healthy
    assert level([tenure_days: 40], settings) == :healthy
    assert level([api_calls: {600, 1_000}], settings) == :healthy
    assert level([interval: "year", days_to_renewal: 45], settings) == :healthy
  end
end
