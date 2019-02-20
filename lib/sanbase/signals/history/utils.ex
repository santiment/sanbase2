defmodule Sanbase.Signals.History.Utils do
  import Sanbase.Signals.Utils

  def percent_change_calculations_with_cooldown(values, percent_threshold, cooldown) do
    {percent_change_calculations, _} =
      values
      |> Enum.map(fn {grouped_value, current} ->
        percent_change(grouped_value, current)
      end)
      |> Enum.reduce({[], 0}, fn
        percent_change, {accumulated_calculations, 0} when percent_change > percent_threshold ->
          {[{percent_change, true} | accumulated_calculations], cooldown}

        percent_change, {accumulated_calculations, 0} ->
          {[{percent_change, false} | accumulated_calculations], 0}

        percent_change, {accumulated_calculations, cooldown_left} ->
          {[{percent_change, false} | accumulated_calculations], cooldown_left - 1}
      end)

    percent_change_calculations |> Enum.reverse()
  end

  def average([]), do: 0

  def average(values) do
    Float.round(Enum.sum(values) / length(values), 2)
  end
end
