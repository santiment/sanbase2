defmodule Sanbase.Prices.Store do
  # A module for storing and fetching pricing data from a time series data store
  #
  # Currently using InfluxDB for the time series data.
  #
  # There is a single database at the moment, which contains simple average
  # price data for a given currency pair within a given interval. The current
  # interval is about 5 mins (+/- 3 seconds). The timestamps are stored as
  # nanoseconds
  use Sanbase.Influxdb.Store

  alias Sanbase.Prices.Store
  alias Sanbase.Influxdb.Measurement

  def fetch_price_points!(pair, from, to) do
    fetch_query(pair, from, to)
    |> q()
    |> case do
      {:ok, result} ->
        result

      {:error, error} ->
        raise(error)
    end
  end

  def fetch_prices_with_resolution(pair, from, to, resolution) do
    # fill(none) skips intervals with no data to report instead of returning null
    ~s/SELECT MEAN(price), LAST(volume), MEAN(marketcap)
    FROM "#{pair}"
    WHERE time >= #{DateTime.to_unix(from, :nanoseconds)}
    AND time <= #{DateTime.to_unix(to, :nanoseconds)}
    GROUP BY time(#{resolution}) fill(none)/
    |> q()
  end

  def fetch_prices_with_resolution!(pair, from, to, resolution) do
    case fetch_prices_with_resolution(pair, from, to, resolution) do
      {:ok, result} ->
        result

      {:error, error} ->
        raise(error)
    end
  end

  def fetch_mean_volume(pair, from, to) do
    ~s/SELECT MEAN(volume)
    FROM "#{pair}"
    WHERE time >= #{DateTime.to_unix(from, :nanoseconds)}
    AND time <= #{DateTime.to_unix(to, :nanoseconds)}/
    |> q()
  end

  def q(query) do
    Store.query(query)
    |> parse_price_series
  end

  defp fetch_query(pair, from, to) do
    ~s/SELECT time, price, volume, marketcap
    FROM "#{pair}"
    WHERE time >= #{DateTime.to_unix(from, :nanoseconds)}
    AND time <= #{DateTime.to_unix(to, :nanoseconds)}/
  end

  defp parse_price_series(%{results: [%{error: error}]}), do: {:error, error}

  defp parse_price_series(%{
         results: [
           %{
             series: [
               %{
                 values: price_series
               }
             ]
           }
         ]
       }) do
    result =
      price_series
      |> Enum.map(fn [iso8601_datetime | tail] ->
        {:ok, datetime, _} = DateTime.from_iso8601(iso8601_datetime)
        [datetime | tail]
      end)

    {:ok, result}
  end

  defp parse_price_series(_), do: {:ok, []}

  def last_record(pair) do
    ~s/SELECT LAST(price), marketcap, volume from "#{pair}"/
    |> Store.query()
    |> parse_record
  end

  def fetch_last_price_point_before(pair, timestamp) do
    ~s/SELECT LAST(price), marketcap, volume
    FROM "#{pair}"
    WHERE time <= #{DateTime.to_unix(timestamp, :nanoseconds)}/
    |> Store.query()
    |> parse_record
  end

  defp parse_record(%{
         results: [
           %{
             series: [
               %{
                 values: [[iso8601_datetime, price, marketcap, volume]]
               }
             ]
           }
         ]
       }) do
    {:ok, datetime, _} = DateTime.from_iso8601(iso8601_datetime)

    {datetime, price, marketcap, volume}
  end

  defp parse_record(_) do
    nil
  end
end
