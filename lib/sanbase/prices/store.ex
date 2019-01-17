defmodule Sanbase.Prices.Store do
  @moduledoc ~s"""
    A module for storing and fetching pricing data from a time series data store
    Currently using InfluxDB for the time series data.

    There is a single database at the moment, which contains simple average
    price data for a given currency pair within a given interval. The current
    interval is about 5 mins (+/- 3 seconds). The timestamps are stored as
    nanoseconds
  """
  use Sanbase.Influxdb.Store

  require Logger

  alias __MODULE__
  alias Sanbase.Influxdb.Measurement

  @last_history_price_cmc_measurement "sanbase-internal-last-history-price-cmc"
  def last_history_price_cmc_measurement() do
    @last_history_price_cmc_measurement
  end

  @doc ~s"""
    Fetch all price points in the given `from-to` time interval from `measurement`.
  """
  def fetch_price_points(measurement, from, to) do
    fetch_query(measurement, from, to)
    |> Store.query()
    |> parse_time_series()
  end

  @doc ~s"""
    Fetch open, close, high, low price values for every interval between from-to
  """
  def fetch_ohlc(measurement, from, to, interval) do
    fetch_ohlc_query(measurement, from, to, interval)
    |> Store.query()
    |> parse_time_series()
  end

  @doc ~s"""
    Fetch all price points in the given `from-to` time interval from `measurement`.
  """
  def fetch_price_points!(measurement, from, to) do
    case fetch_price_points(measurement, from, to) do
      {:ok, result} ->
        result

      {:error, error} ->
        raise(error)
    end
  end

  def fetch_prices_with_resolution(measurement, from, to, resolution) do
    fetch_prices_with_resolution_query(measurement, from, to, resolution)
    |> Store.query()
    |> parse_time_series()
  end

  def fetch_prices_with_resolution!(pair, from, to, resolution) do
    case fetch_prices_with_resolution(pair, from, to, resolution) do
      {:ok, result} ->
        result

      {:error, error} ->
        raise(error)
    end
  end

  def fetch_mean_volume(measurement, from, to) do
    fetch_mean_volume_query(measurement, from, to)
    |> Store.query()
    |> parse_time_series()
  end

  def fetch_average_price(measurement, from, to) do
    fetch_average_price_query(measurement, from, to)
    |> Store.query()
    |> parse_time_series()
    |> case do
      {:ok, [[_datetime, avg_price_usd, avg_price_btc]]} ->
        {:ok, {avg_price_usd, avg_price_btc}}

      _ ->
        {:error, "Cannot fetch average prices for #{measurement}"}
    end
  end

  def update_last_history_datetime_cmc(slug, last_updated_datetime) do
    %Measurement{
      timestamp: 0,
      fields: %{last_updated: last_updated_datetime |> DateTime.to_unix(:nanoseconds)},
      tags: [ticker_cmc_id: slug],
      name: @last_history_price_cmc_measurement
    }
    |> Store.import()
  end

  def last_history_datetime_cmc(ticker_cmc_id) do
    last_history_datetime_cmc_query(ticker_cmc_id)
    |> Store.query()
    |> parse_time_series()
    |> case do
      {:ok, [[_, iso8601_datetime | _rest]]} ->
        {:ok, datetime} = DateTime.from_unix(iso8601_datetime, :nanoseconds)
        {:ok, datetime}

      {:ok, []} ->
        {:ok, nil}

      {:error, error} ->
        {:error, error}
    end
  end

  def last_history_datetime_cmc!(ticker) do
    case last_history_datetime_cmc(ticker) do
      {:ok, datetime} -> datetime
      {:error, error} -> raise(error)
    end
  end

  def fetch_last_price_point_before(measurement, timestamp) do
    fetch_last_price_point_before_query(measurement, timestamp)
    |> Store.query()
    |> parse_time_series()
  end

  def fetch_combined_mcap_volume(measurement_slugs, from, to, interval) do
    measurements_str = measurement_slugs |> Enum.map(fn x -> ~s/"#{x}"/ end) |> Enum.join(", ")

    fetch_combined_mcap_volume_query(measurements_str, from, to, interval)
    |> Store.query()
    |> combine_results_mcap_volume()
  end

  def fetch_volume_mcap_multiple_measurements(measurement_slug_map, from, to) do
    measurements_str =
      measurement_slug_map |> Map.keys() |> Enum.map(fn x -> ~s/"#{x}"/ end) |> Enum.join(", ")

    fetch_volume_mcap_multiple_measurements_query(measurements_str, from, to)
    |> Store.query()
    |> volume_mcap_multiple_measurements_reducer(measurement_slug_map)
  end

  def volume_over_threshold(measurements, from, to, threshold) do
    mean_volume_for_period_query(measurements, from, to)
    |> Store.query()
    |> filter_volume_over_threshold(threshold)
  end

  def all_with_data_after_datetime(datetime) do
    datetime_unix_ns = DateTime.to_unix(datetime, :nanoseconds)

    ~s/SELECT last_updated, ticker_cmc_id FROM "#{@last_history_price_cmc_measurement}"
    WHERE ticker_cmc_id != "" AND last_updated >= #{datetime_unix_ns}/
    |> Store.query()
    |> parse_time_series()
  end

  # Helper functions

  defp filter_volume_over_threshold(
         %{
           results: [
             %{
               series: [_ | _] = series
             }
           ]
         },
         threshold
       ) do
    series
    |> Enum.map(fn %{name: name, values: [[_datetime, volume]]} ->
      {name, volume}
    end)
    |> Enum.reject(fn {_, volume} -> volume < threshold end)
    |> Enum.map(fn {name, _} -> name end)
  end

  defp filter_volume_over_threshold(_, _), do: []

  defp fetch_query(measurement, from, to) do
    ~s/SELECT time, price_usd, price_btc, marketcap_usd, volume_usd
    FROM "#{measurement}"
    WHERE time >= #{DateTime.to_unix(from, :nanoseconds)}
    AND time <= #{DateTime.to_unix(to, :nanoseconds)}/
  end

  defp fetch_ohlc_query(measurement, from, to, interval) do
    ~s/SELECT
     time,
     first(price_usd) as open,
     max(price_usd) as high,
     min(price_usd) as low,
     last(price_usd) as close,
     mean(price_usd) as avg
     FROM "#{measurement}"
     WHERE time >= #{DateTime.to_unix(from, :nanoseconds)}
     AND time <= #{DateTime.to_unix(to, :nanoseconds)}
     GROUP BY time(#{interval})
     FILL(0)/
  end

  defp fetch_prices_with_resolution_query(measurement, from, to, resolution) do
    ~s/SELECT MEAN(price_usd), MEAN(price_btc), MEAN(marketcap_usd), LAST(volume_usd)
    FROM "#{measurement}"
    WHERE time >= #{DateTime.to_unix(from, :nanoseconds)}
    AND time <= #{DateTime.to_unix(to, :nanoseconds)}
    GROUP BY time(#{resolution}) fill(none)/
  end

  defp fetch_last_price_point_before_query(measurement, timestamp) do
    ~s/SELECT LAST(price_usd), price_btc, marketcap_usd, volume_usd
    FROM "#{measurement}"
    WHERE time <= #{DateTime.to_unix(timestamp, :nanoseconds)}/
  end

  defp fetch_mean_volume_query(measurement, from, to) do
    ~s/SELECT MEAN(volume_usd)
    FROM "#{measurement}"
    WHERE time >= #{DateTime.to_unix(from, :nanoseconds)}
    AND time <= #{DateTime.to_unix(to, :nanoseconds)}/
  end

  defp fetch_average_price_query(measurement, from, to) do
    ~s/SELECT MEAN(price_usd), MEAN(price_btc)
    FROM "#{measurement}"
    WHERE time >= #{DateTime.to_unix(from, :nanoseconds)}
    AND time <= #{DateTime.to_unix(to, :nanoseconds)}/
  end

  defp last_history_datetime_cmc_query(ticker_cmc_id) do
    ~s/SELECT * FROM "#{@last_history_price_cmc_measurement}"
    WHERE ticker_cmc_id = '#{ticker_cmc_id}'/
  end

  defp fetch_volume_mcap_multiple_measurements_query(measurements_str, from, to) do
    ~s/SELECT LAST(volume_usd), LAST(marketcap_usd)
      FROM #{measurements_str}
      WHERE time >= #{DateTime.to_unix(from, :nanoseconds)}
      AND time <= #{DateTime.to_unix(to, :nanoseconds)}/
  end

  defp fetch_combined_mcap_volume_query(measurements_str, from, to, resolution) do
    ~s/SELECT MEAN(volume_usd), MEAN(marketcap_usd)
       FROM #{measurements_str}
       WHERE time >= #{DateTime.to_unix(from, :nanoseconds)}
       AND time <= #{DateTime.to_unix(to, :nanoseconds)}
       GROUP BY time(#{resolution}) fill(0)/
  end

  defp volume_mcap_multiple_measurements_reducer(%{results: [%{error: error}]}, _),
    do: {:error, error}

  defp volume_mcap_multiple_measurements_reducer(
         %{results: [%{series: series}]},
         measurement_slug_map
       ) do
    slugs = series |> Enum.map(fn s -> measurement_slug_map[s.name] end)
    values = series |> Enum.map(& &1.values)
    volume_values = values |> Enum.map(fn [[_, vol, _]] -> vol end)
    combined_mcap = values |> Enum.reduce(0, fn [[_, _, mcap]], acc -> acc + mcap end)
    marketcap_values = values |> Enum.map(fn [[_, _, mcap]] -> mcap end)

    marketcap_percent =
      marketcap_values |> Enum.map(fn mcap -> Float.round(mcap / combined_mcap, 5) end)

    result = Enum.zip([slugs, volume_values, marketcap_values, marketcap_percent])

    {:ok, result}
  end

  defp volume_mcap_multiple_measurements_reducer(_, _), do: {:error, nil}

  defp combine_results_mcap_volume(%{results: [%{error: error}]}), do: {:error, error}

  defp combine_results_mcap_volume(%{results: [%{series: series}]}) do
    result =
      series
      |> Enum.map(fn %{values: values} -> values end)
      |> Enum.zip()
      |> Enum.map(&Tuple.to_list/1)
      |> Enum.map(fn [[iso8601_datetime, _, _] | _] = projects_data ->
        {:ok, datetime, _} = DateTime.from_iso8601(iso8601_datetime)

        {combined_volume, combined_mcap} =
          projects_data
          |> Enum.reduce({0, 0}, fn [_, volume, mcap], {v, m} -> {v + volume, m + mcap} end)

        %{datetime: datetime, volume: combined_volume, marketcap: combined_mcap}
      end)

    {:ok, result}
  end

  defp combine_results_mcap_volume(_), do: {:ok, []}

  defp mean_volume_for_period_query(measurements, from, to) do
    ~s/SELECT MEAN(volume_usd) as volume
    FROM #{measurements}
    WHERE time >= #{DateTime.to_unix(from, :nanoseconds)}
    AND time <= #{DateTime.to_unix(to, :nanoseconds)}/
  end
end
