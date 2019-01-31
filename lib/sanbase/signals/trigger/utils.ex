defmodule Sanbase.Signals.Utils do
  def percent_change(0, _current_daa), do: 0
  def percent_change(nil, _current_daa), do: 0

  def percent_change(previous, current) do
    Float.round((current - previous) / previous * 100)
  end
end
