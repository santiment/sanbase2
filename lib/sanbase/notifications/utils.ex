defmodule Sanbase.Notifications.Utils do
  def time_difference(dt1, dt2) do
    case Timex.diff(dt1, dt2, :seconds) |> abs() do
      x when x < 3600 ->
        "#{div(x, 60)} minutes"

      x when x <= 7200 ->
        "1 hour"

      x when x < 86_400 ->
        "#{div(x, 3600)} hours"
    end
  end
end
