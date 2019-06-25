defmodule Sanbase.Signals.OperationEvaluation do
  defguard is_between_exclusive(value, low, high)
           when is_number(value) and is_number(low) and is_number(high) and value > low and
                  value < high

  defguard is_percent_change_moving_up(percent_change, percent)
           when percent_change > 0 and percent_change >= percent

  defguard is_percent_change_moving_down(percent_change, percent)
           when percent_change < 0 and abs(percent_change) >= percent

  def operation_triggered?(value, %{above: above}), do: value >= above
  def operation_triggered?(value, %{below: below}), do: value <= below

  def operation_triggered?(value, %{inside_channel: [lower, upper]}) when lower < upper do
    value >= lower and value <= upper
  end

  def operation_triggered?(value, %{outside_channel: [lower, upper]}) when lower < upper do
    value <= lower or value >= upper
  end

  def operation_triggered?(percent_change, %{percent_up: percent})
      when is_percent_change_moving_up(percent_change, percent) do
    true
  end

  def operation_triggered?(percent_change, %{percent_down: percent})
      when is_percent_change_moving_down(percent_change, percent) do
    true
  end

  def operation_triggered?(amount_changed, %{amount_up: amount})
      when is_number(amount_changed) and is_number(amount) and amount > 0 do
    amount_changed >= amount
  end

  def operation_triggered?(amount_changed, %{amount_down: amount})
      when is_number(amount_changed) and is_number(amount) and amount > 0 do
    amount_changed < 0 and abs(amount_changed) >= amount
  end

  def operation_triggered?(_, _), do: false
end
