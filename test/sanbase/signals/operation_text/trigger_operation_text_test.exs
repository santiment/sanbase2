defmodule Sanbase.Signal.TriggerOperationTextTest do
  use Sanbase.DataCase, async: true

  test "all_of text" do
    value = %{
      identifier: "santiment",
      current: 15,
      previous: 10,
      previous_average: 12,
      absolute_change: 5,
      percent_change: 50
    }

    operation = %{all_of: [%{amount_up: 4}, %{above: 10}, %{below: 20}]}

    text = Sanbase.Signal.OperationText.to_text(value, operation)
    assert text =~ "is below 20"
    assert text =~ "is above 10"
    assert text =~ "increased by 5"
  end

  test "some_of text" do
    value = %{
      identifier: "santiment",
      current: 15,
      previous: 10,
      previous_average: 12,
      absolute_change: 5,
      percent_change: 50
    }

    operation = %{some_of: [%{amount_up: 4}, %{amount_down: 10}, %{above: 10}, %{below: 2}]}

    text = Sanbase.Signal.OperationText.to_text(value, operation)
    assert text =~ "is above 10"
    assert text =~ "increased by 5"
    refute text =~ "is below 2"
    refute text =~ "decreased by 10"
  end

  test "none_of text" do
    value = %{
      identifier: "santiment",
      current: 15,
      previous: 10,
      previous_average: 12,
      absolute_change: 5,
      percent_change: 50
    }

    operation = %{none_of: [%{amount_up: 40}, %{amount_down: 10}, %{above: 100}, %{below: 2}]}

    text = Sanbase.Signal.OperationText.to_text(value, operation)

    assert text =~ "is not above 100"
    assert text =~ "did not increase by 40"
    assert text =~ "is not below 2"
    assert text =~ "did not decrease by 10"
  end
end
