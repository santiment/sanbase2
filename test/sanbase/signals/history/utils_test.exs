defmodule Sanbase.Signals.TriggerHistoryUtilsTest do
  use Sanbase.DataCase, async: true

  alias Sanbase.Signals.History.Utils

  test "#percent_change_calculations_with_cooldown" do
    percent_changes = [{5, 6}, {10, 11}, {7, 8}, {3, 2}, {100, 105}, {4, 3}, {8, 10}, {9, 11}]

    percent_threshold = 5.0

    percent_change_calculations =
      Utils.percent_change_calculations_with_cooldown(percent_changes, percent_threshold, 2)

    assert percent_change_calculations |> length() == 8
    assert filter_with_bigger_threshold(percent_change_calculations) |> length() == 3

    # no cooldown
    percent_change_calculations =
      Utils.percent_change_calculations_with_cooldown(percent_changes, percent_threshold, 0)

    assert filter_with_bigger_threshold(percent_change_calculations) |> length() == 6

    percent_change_calculations =
      Utils.percent_change_calculations_with_cooldown(percent_changes, %{percent_up: 5.0}, 2)

    assert percent_change_calculations |> length() == 8
    assert filter_with_bigger_threshold(percent_change_calculations) |> length() == 3
  end

  test "#average" do
    assert Utils.average([4, 6, 8, 2]) == 5.0
    assert Utils.average([]) == 0
    assert Utils.average([0.126]) == 0.13
  end

  property "average is always between min and max when list of integers" do
    check all list <- list_of(positive_integer(), min_length: 1) do
      average = Utils.average(list)
      min = Enum.min(list)
      max = Enum.max(list)
      assert average >= min and average <= max
    end
  end

  property "average is always between min -1 and max + 1 when floats" do
    check all list <- list_of(float(min: 0.00), min_length: 1) do
      average = Utils.average(list)
      min = Enum.min(list)
      max = Enum.max(list)
      assert average >= min - 1 and average <= max + 1
    end
  end

  defp filter_with_bigger_threshold(percent_change_calculations) do
    Enum.filter(percent_change_calculations, fn {_percent_change, is_bigger_than_threshold?} ->
      is_bigger_than_threshold?
    end)
  end
end
