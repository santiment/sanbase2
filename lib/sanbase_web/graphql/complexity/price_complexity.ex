defmodule SanbaseWeb.Graphql.PriceComplexity do
  require Logger

  @doc "Returns the number of intervals in the period 'from-to'"
  def history_price(%{from: from, to: to, interval: interval}, child_complexity) do
    from_unix = DateTime.to_unix(from, :second)
    to_unix = DateTime.to_unix(to, :second)

    interval_type = String.last(interval)

    interval_seconds =
      String.slice(interval, 0..-2)
      |> String.to_integer()
      |> str_to_sec(interval_type)

    (child_complexity * ((to_unix - from_unix) / interval_seconds))
    |> Float.floor()
    |> Kernel.trunc()
  end

  defp str_to_sec(seconds, "s"), do: seconds
  defp str_to_sec(hours, "h"), do: hours * 60 * 60
  defp str_to_sec(minutes, "m"), do: minutes * 60
  defp str_to_sec(days, "d"), do: days * 60 * 60 * 24
  defp str_to_sec(weeks, "w"), do: weeks * 60 * 60 * 24 * 7
end