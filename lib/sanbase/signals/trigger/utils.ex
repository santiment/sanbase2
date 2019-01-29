defmodule Sanbase.Signals.Utils do
  def percent_change(_current_daa, 0), do: 0
  def percent_change(_current_daa, nil), do: 0

  def percent_change(current_daa, avg_daa) do
    Float.round(current_daa / avg_daa * 100)
  end
end
