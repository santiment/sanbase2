defmodule Sanbase.Alert.OperationEvaluation do
  @moduledoc ~s"""
  Module providing a single function operation_triggered?/2 that by a given
  value and operation returns true or false
  """
  def operation_triggered?(nil, _), do: false

  def operation_triggered?(value, %{some_of: operations}) when is_list(operations) do
    operations
    |> Enum.map(fn op -> operation_triggered?(value, op) end)
    |> Enum.member?(true)
  end

  def operation_triggered?(value, %{all_of: operations}) when is_list(operations) do
    operations
    |> Enum.map(fn op -> operation_triggered?(value, op) end)
    |> Enum.all?(&(&1 == true))
  end

  def operation_triggered?(value, %{none_of: operations}) when is_list(operations) do
    operations
    |> Enum.map(fn op -> operation_triggered?(value, op) end)
    |> Enum.all?(&(&1 == false))
  end

  # Above
  def operation_triggered?(%{current: nil}, %{above: _}), do: false
  def operation_triggered?(%{current: value}, %{above: above}), do: value > above
  def operation_triggered?(value, %{above: above}), do: value > above

  # Below
  def operation_triggered?(%{current: nil}, %{below: _}), do: false
  def operation_triggered?(%{current: value}, %{below: below}), do: value < below
  def operation_triggered?(value, %{below: below}), do: value < below

  # Above or equal
  def operation_triggered?(%{current: nil}, %{above_or_equal: _}), do: false

  def operation_triggered?(%{current: value}, %{above_or_equal: _} = op), do: operation_triggered?(value, op)

  def operation_triggered?(value, %{above_or_equal: above_or_equal}), do: value >= above_or_equal

  # Below or equal
  def operation_triggered?(%{current: nil}, %{below_or_equal: _}), do: false

  def operation_triggered?(%{current: value}, %{below_or_equal: _} = op), do: operation_triggered?(value, op)

  def operation_triggered?(value, %{below_or_equal: below_or_equal}), do: value <= below_or_equal

  # Inside channel
  def operation_triggered?(%{current: nil}, %{inside_channel: _}), do: false

  def operation_triggered?(%{current: value}, %{inside_channel: [lower, upper]}) when lower < upper,
    do: value >= lower and value <= upper

  def operation_triggered?(value, %{inside_channel: [lower, upper]}) when lower < upper,
    do: value >= lower and value <= upper

  # Outside channel
  def operation_triggered?(%{current: nil}, %{outside_channel: _}), do: false

  def operation_triggered?(%{current: value}, %{outside_channel: [lower, upper]}) when lower < upper,
    do: value <= lower or value >= upper

  def operation_triggered?(value, %{outside_channel: [lower, upper]}) when lower < upper,
    do: value <= lower or value >= upper

  # Percent up

  def operation_triggered?(%{percent_change: nil}, %{percent_up: _}), do: false

  def operation_triggered?(%{percent_change: percent_change}, %{percent_up: percent}),
    do: percent_change > 0 and percent_change >= percent

  def operation_triggered?(percent_change, %{percent_up: percent}), do: percent_change > 0 and percent_change >= percent

  # Percent down
  def operation_triggered?(%{percent_change: nil}, %{percent_down: _}), do: false

  def operation_triggered?(%{percent_change: percent_change}, %{percent_down: percent}),
    do: percent_change < 0 and abs(percent_change) >= percent

  def operation_triggered?(percent_change, %{percent_down: percent}),
    do: percent_change < 0 and abs(percent_change) >= percent

  # Amount up
  def operation_triggered?(%{absolute_change: nil}, %{amount_up: _}), do: false

  def operation_triggered?(%{absolute_change: amount_changed}, %{amount_up: amount}),
    do: amount_changed > 0 and amount_changed >= amount

  def operation_triggered?(amount_changed, %{amount_up: amount}), do: amount_changed > 0 and amount_changed >= amount

  # Amount down
  def operation_triggered?(%{absolute_change: nil}, %{amount_down: _}), do: false

  def operation_triggered?(%{absolute_change: amount_changed}, %{amount_down: amount}),
    do: amount_changed < 0 and abs(amount_changed) >= amount

  def operation_triggered?(amount_changed, %{amount_down: amount}),
    do: amount_changed < 0 and abs(amount_changed) >= amount

  def operation_triggered?(_, _), do: false
end
