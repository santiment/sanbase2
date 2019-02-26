defmodule Sanbase.Signals.Utils do
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
end
