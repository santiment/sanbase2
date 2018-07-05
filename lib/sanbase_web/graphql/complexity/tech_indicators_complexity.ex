defmodule SanbaseWeb.Graphql.Complexity.TechIndicatorsComplexity do
  require Logger

  @doc ~S"""
  Internal services use basic authentication. Return complexity = 0 to allow them
  to access everything without limits.
  """
  def macd(_, _, %Absinthe.Complexity{context: %{auth: %{auth_method: :basic}}}) do
    0
  end

  def macd(%{from: from, to: to, interval: interval}, _child_complexity, _) do
    get_complexity(from, to, interval)
  end

  @doc ~S"""
  Internal services use basic authentication. Return complexity = 0 to allow them
  to access everything without limits.
  """
  def rsi(_, _, %Absinthe.Complexity{context: %{auth: %{auth_method: :basic}}}) do
    0
  end

  @doc ~S"""
  For max complexity 5000 we allow 1000 values
  """
  def rsi(%{from: from, to: to, interval: interval}, _child_complexity, _) do
    get_complexity(from, to, interval)
  end

  @doc ~S"""
  Internal services use basic authentication. Return complexity = 0 to allow them
  to access everything without limits.
  """
  def price_volume_diff(_, _, %Absinthe.Complexity{context: %{auth: %{auth_method: :basic}}}) do
    0
  end

  @doc ~S"""
  For max complexity 5000 we allow 1000 values
  """
  def price_volume_diff(%{from: from, to: to, interval: interval}, _child_complexity, _) do
    get_complexity(from, to, interval)
  end

  @doc ~S"""
  Internal services use basic authentication. Return complexity = 0 to allow them
  to access everything without limits.
  """
  def twitter_mention_count(_, _, %Absinthe.Complexity{context: %{auth: %{auth_method: :basic}}}) do
    0
  end

  @doc ~S"""
  For max complexity 5000 we allow 1000 values
  """
  def twitter_mention_count(%{from: from, to: to, interval: interval}, _child_complexity, _) do
    get_complexity(from, to, interval)
  end

  @doc ~S"""
  Internal services use basic authentication. Return complexity = 0 to allow them
  to access everything without limits.
  """
  def emojis_sentiment(_, _, %Absinthe.Complexity{context: %{auth: %{auth_method: :basic}}}) do
    0
  end

  @doc ~S"""
  For max complexity 5000 we allow 1000 values
  """
  def emojis_sentiment(%{from: from, to: to, interval: interval}, _child_complexity, _) do
    get_complexity(from, to, interval)
  end

  # Helper functions

  # For max complexity 5000 we allow 1000 values
  defp get_complexity(from_datetime, to_datetime, interval) do
    get_number_of_intervals(from_datetime, to_datetime, interval)
    |> case do
      # should be larger than the max complexity
      nil ->
        1_000_000

      intervals_count ->
        Kernel.trunc(intervals_count * 5)
    end
  end

  defp get_number_of_intervals(from_datetime, to_datetime, interval) do
    with from_seconds <- DateTime.to_unix(from_datetime, :second),
         to_seconds <- DateTime.to_unix(to_datetime, :second),
         true <- to_seconds > from_seconds,
         interval_seconds <- get_interval_seconds(interval),
         false <- is_nil(interval_seconds) and interval_seconds != 0 do
      (to_seconds - from_seconds) / interval_seconds
    else
      _ -> nil
    end
  end

  defp get_interval_seconds(interval) do
    with %{"number" => number_str, "unit" => unit} <-
           Regex.named_captures(~r/^(?<number>\d+)(?<unit>d|h|m|s)$/, interval),
         number <- String.to_integer(number_str) do
      case unit do
        "w" -> number * 86400 * 7
        "d" -> number * 86400
        "h" -> number * 3600
        "m" -> number * 60
        "s" -> number
        _ -> nil
      end
    else
      _ -> nil
    end
  end
end
