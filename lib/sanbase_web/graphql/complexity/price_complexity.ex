defmodule SanbaseWeb.Graphql.Complexity.PriceComplexity do
  require Logger

  @doc ~S"""
  Internal services use basic authentication. Return complexity = 0 to allow them
  to access everything without limits.
  """
  def current_prices(_,_, %Absinthe.Complexity{context: %{auth: %{auth_method: :basic}}}) do
    0
  end

  @doc ~S"""
  Returns the complexity of the query. It is the number of returned fields multiplied by 100.
  The multiplier is big because the current implementation makes a separate DB query for
  each ticker
  """
  def current_prices(%{tickers: tickers}, child_complexity, _) do
    Enum.count(tickers) * child_complexity * 100
  end

  @doc ~S"""
  Internal services use basic authentication. Return complexity = 0 to allow them
  to access everything without limits.
  """
  def history_price(_,_, %Absinthe.Complexity{context: %{auth: %{auth_method: :basic}}}) do
    0
  end

  @doc ~S"""
  Returns the complexity of the query. It is the number of intervals in the period
  'from-to' multiplied by the child complexity. The child complexity is the number
  of fields that will be returned for a single price point. The calculation is done
  based only on the supplied arguments and avoids accessing the DB if the query
  is rejected.
  """
  def history_price(%{from: from, to: to, interval: interval}, child_complexity, _) do
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
  defp str_to_sec(minutes, "m"), do: minutes * 60
  defp str_to_sec(hours, "h"), do: hours * 60 * 60
  defp str_to_sec(days, "d"), do: days * 60 * 60 * 24
  defp str_to_sec(weeks, "w"), do: weeks * 60 * 60 * 24 * 7
end
