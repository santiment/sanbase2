defmodule SanbaseWeb.Graphql.Complexity.PriceComplexity do
  require Logger

  @doc ~S"""
  Internal services use basic authentication. Return complexity = 0 to allow them
  to access everything without limits.
  """
  def current_prices(_, _, %Absinthe.Complexity{context: %{auth: %{auth_method: :basic}}}) do
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
  def history_price(_, _, %Absinthe.Complexity{context: %{auth: %{auth_method: :basic}}}) do
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
    interval = if interval == "", do: "1d", else: interval

    interval_seconds = Sanbase.DateTimeUtils.str_to_sec(interval)

    (child_complexity * ((to_unix - from_unix) / interval_seconds))
    |> Float.floor()
    |> Kernel.trunc()
  end
end
