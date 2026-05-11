defmodule Sanbase.Alert.TriggerHistoryUtilsTest do
  use ExUnit.Case, async: true

  alias Sanbase.Alert.History.Utils

  describe "percent_change_calculations_with_cooldown/3" do
    test "with cooldown of 2, suppresses triggers during cooldown" do
      values = [{5, 6}, {10, 11}, {7, 8}, {3, 2}, {100, 105}, {4, 3}, {8, 10}, {9, 11}]
      operation = %{percent_up: 5.0}

      result = Utils.percent_change_calculations_with_cooldown(values, operation, 2)

      assert length(result) == 8
      assert count_triggered(result) == 3
    end

    test "with cooldown of 0, all matching triggers fire" do
      values = [{5, 6}, {10, 11}, {7, 8}, {3, 2}, {100, 105}, {4, 3}, {8, 10}, {9, 11}]
      operation = %{percent_up: 5.0}

      result = Utils.percent_change_calculations_with_cooldown(values, operation, 0)

      assert count_triggered(result) == 6
    end

    test "returns empty list for empty input" do
      result = Utils.percent_change_calculations_with_cooldown([], %{percent_up: 5.0}, 0)
      assert result == []
    end

    test "no triggers when threshold is very high" do
      values = [{100, 101}, {100, 102}]
      operation = %{percent_up: 50.0}

      result = Utils.percent_change_calculations_with_cooldown(values, operation, 0)
      assert count_triggered(result) == 0
    end

    test "every value triggers when threshold is very low" do
      values = [{100, 110}, {100, 120}, {100, 130}]
      operation = %{percent_up: 1.0}

      result = Utils.percent_change_calculations_with_cooldown(values, operation, 0)
      assert count_triggered(result) == 3
    end
  end

  defp count_triggered(results) do
    Enum.count(results, fn {_pct, triggered?} -> triggered? end)
  end
end
