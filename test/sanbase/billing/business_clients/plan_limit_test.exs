defmodule Sanbase.Billing.BusinessClients.PlanLimitTest do
  use ExUnit.Case, async: true

  alias Sanbase.Billing.BusinessClients.PlanLimit

  @limit 600_000
  @today ~D[2026-11-15]

  # Calls for the six full months before November 2026, oldest first.
  defp months(calls) do
    calls
    |> Enum.with_index()
    |> Map.new(fn {count, i} -> {Date.shift(~D[2026-05-01], month: i), count} end)
  end

  test "the last six full months, oldest first, as shares of the limit" do
    result = PlanLimit.assess(months([0, 60_000, 0, 0, 300_000, 480_000]), @limit, @today)

    assert Enum.map(result.months, & &1.month) ==
             [
               ~D[2026-05-01],
               ~D[2026-06-01],
               ~D[2026-07-01],
               ~D[2026-08-01],
               ~D[2026-09-01],
               ~D[2026-10-01]
             ]

    assert Enum.map(result.months, & &1.share) == [0.0, 0.1, 0.0, 0.0, 0.5, 0.8]
    assert result.last_month == %{month: ~D[2026-10-01], calls: 480_000, share: 0.8}
    assert result.months_at_high == 1
    assert result.limit == @limit
  end

  test "this month's pace spreads the calls so far over the whole month" do
    calls = Map.put(months([0, 0, 0, 0, 0, 0]), ~D[2026-11-01], 150_000)
    result = PlanLimit.assess(calls, @limit, @today)

    # 150,000 in 15 of November's 30 days.
    assert result.pace == %{calls: 300_000, share: 0.5, partial?: false}
  end

  describe "upsell" do
    test "two months at 80% or more, and still at half the limit last month" do
      result = PlanLimit.assess(months([500_000, 0, 490_000, 0, 0, 310_000]), @limit, @today)

      assert result.upsell?
      assert result.upsell_reason =~ "80% or more of the monthly limit in 2 of the last 6 months"
    end

    test "two high months long ago and quiet since is not a candidate" do
      result = PlanLimit.assess(months([500_000, 490_000, 0, 0, 0, 100_000]), @limit, @today)

      refute result.upsell?
      assert result.upsell_reason == nil
    end

    test "two high months and quiet last month, but busy again this month" do
      calls =
        [500_000, 490_000, 0, 0, 0, 100_000]
        |> months()
        |> Map.put(~D[2026-11-01], 160_000)

      assert PlanLimit.assess(calls, @limit, @today).upsell?
    end

    test "on pace for 90% of the limit this month alone" do
      calls = Map.put(months([0, 0, 0, 0, 0, 0]), ~D[2026-11-01], 280_000)
      result = PlanLimit.assess(calls, @limit, @today)

      assert result.upsell?
      assert result.upsell_reason == "On pace for 93% of the monthly limit this month"
    end

    test "the pace does not count in the first days of a month" do
      calls = Map.put(months([0, 0, 0, 0, 0, 0]), ~D[2026-11-01], 200_000)

      refute PlanLimit.assess(calls, @limit, ~D[2026-11-06]).upsell?
      assert PlanLimit.assess(calls, @limit, ~D[2026-11-07]).upsell?
    end
  end

  test "without a numeric limit there are no shares and no upsell" do
    calls = months([600_000, 600_000, 600_000, 600_000, 600_000, 600_000])

    for limit <- [nil, :unlimited] do
      result = PlanLimit.assess(calls, limit, @today)

      assert Enum.all?(result.months, &is_nil(&1.share))
      assert result.pace.share == nil
      refute result.upsell?
    end
  end

  test "percent/1" do
    assert PlanLimit.percent(0.873) == "87%"
    assert PlanLimit.percent(nil) == "-"
  end
end
