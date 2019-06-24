defmodule Sanbase.Signals.TriggerHistoryUtilsTest do
  use Sanbase.DataCase, async: true

  alias Sanbase.Signals.History.Utils

  test "#percent_change_calculations_with_cooldown" do
    percent_changes = [{5, 6}, {10, 11}, {7, 8}, {3, 2}, {100, 105}, {4, 3}, {8, 10}, {9, 11}]

    percent_threshold = %{percent_up: 5.0}

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

  defp filter_with_bigger_threshold(percent_change_calculations) do
    Enum.filter(percent_change_calculations, fn {_percent_change, is_bigger_than_threshold?} ->
      is_bigger_than_threshold?
    end)
  end
end
