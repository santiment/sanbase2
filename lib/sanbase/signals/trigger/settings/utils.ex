defmodule Sanbase.Signals.Utils do
  alias Sanbase.Math

  defguard is_between_exclusive(value, low, high)
           when is_number(value) and is_number(low) and is_number(high) and value > low and
                  value < high

  defguard is_percent_change_moving_up(percent_change, percent)
           when percent_change > 0 and percent_change >= percent

  defguard is_percent_change_moving_down(percent_change, percent)
           when percent_change < 0 and abs(percent_change) >= percent

  def percent_change(0, _current_daa), do: 0
  def percent_change(nil, _current_daa), do: 0

  def percent_change(previous, _current_daa) when is_number(previous) and previous <= 1.0e-6,
    do: 0

  def percent_change(previous, current) when is_number(previous) and is_number(current) do
    Float.round((current - previous) / previous * 100)
  end

  def construct_cache_key(keys) when is_list(keys) do
    data = keys |> Jason.encode!()

    :crypto.hash(:sha256, data)
    |> Base.encode16()
  end

  def chart_url(project, type) do
    Sanbase.Chart.build_embedded_chart(
      project,
      Timex.shift(Timex.now(), days: -90),
      Timex.now(),
      chart_type: type
    )
    |> case do
      [%{image: %{url: chart_url}}] -> chart_url
      _ -> nil
    end
  end

  def round_price(price) when is_between_exclusive(price, 0, 1) do
    Math.to_float(price) |> Float.round(6)
  end

  def round_price(price) when is_number(price) and price >= 1 do
    Math.to_float(price) |> Float.round(2)
  end

  def evaluate_operation(price, %{above: above}), do: price >= above
  def evaluate_operation(price, %{below: below}), do: price <= below

  def evaluate_operation(price, %{inside_channel: inside_channel}) do
    [lower, upper] = inside_channel
    price >= lower and price <= upper
  end

  def evaluate_operation(price, %{outside_channel: outside_channel}) do
    [lower, upper] = outside_channel
    price <= lower or price >= upper
  end

  def percent_operation_triggered?(percent_change, %{percent_up: percent})
      when is_percent_change_moving_up(percent_change, percent),
      do: true

  def percent_operation_triggered?(percent_change, %{percent_down: percent})
      when is_percent_change_moving_down(percent_change, percent),
      do: true

  def percent_operation_triggered?(_, _), do: false
end
