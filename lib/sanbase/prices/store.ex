defmodule Sanbase.Prices.Store do
  @moduledoc ~s"""
    A module for storing and fetching price data from a time series data store
    Currently using InfluxDB for the time series data.

    There is a single database at the moment, which contains simple average
    price data for a given currency pair within a given interval. The current
    interval is about 5 mins (+/- 3 seconds). The timestamps are stored as
    nanoseconds
  """

  use Sanbase.Influxdb.Store

  alias SanbaseWeb.Graphql.Cache
  alias __MODULE__
  alias Sanbase.Influxdb.Measurement

  require Logger

  @last_history_price_cmc_measurement "sanbase-internal-last-history-price-cmc"
  def last_history_price_cmc_measurement() do
    @last_history_price_cmc_measurement
  end

  def first_datetime_total_market(measurements) when is_list(measurements) do
    measurements_str = measurements |> Enum.map(fn x -> ~s/"#{x}"/ end) |> Enum.join(", ")

    ~s/SELECT first(marketcap_usd) FROM #{measurements_str}/
    |> get()
    |> case do
      %{results: [%{series: series}]} ->
        result =
          series
          |> Enum.map(fn %{name: name, values: [[value, _]]} -> {name, value} end)

        {:ok, result}

      error ->
        {:error, error}
    end
  end

  def first_datetime_multiple_measurements([]), do: []

  def first_datetime_multiple_measurements(measurements) when is_list(measurements) do
    measurements_str = measurements |> Enum.map(fn x -> ~s/"#{x}"/ end) |> Enum.join(", ")

    ~s/SELECT first(price_usd) FROM #{measurements_str}/
    |> get()
    |> case do
      %{results: [%{series: series}]} ->
        result =
          series
          |> Enum.map(fn %{name: name, values: [[value, _]]} -> {name, value} end)

        {:ok, result}

      error ->
        {:error, error}
    end
  end

  @doc ~s"""
    Fetch all price points in the given `from-to` time interval from `measurement`.
  """
  def fetch_price_points(measurement, from, to) do
    fetch_query(measurement, from, to)
    |> get()
    |> parse_time_series()
  end

  @doc ~s"""
    Fetch open, close, high, low price values for every interval between from-to
  """
  def fetch_ohlc(measurement, from, to, interval) do
    fetch_ohlc_query(measurement, from, to, interval)
    |> get()
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

  def fetch_prices_with_resolution("TOTAL_ERC20", from, to, resolution) do
    measurements =
      Sanbase.Model.Project.List.erc20_projects()
      |> Enum.map(&Sanbase.Influxdb.Measurement.name_from/1)

    fetch_combined_mcap_volume(measurements, from, to, resolution)
  end

  def fetch_prices_with_resolution(measurement, from, to, resolution) do
    fetch_prices_with_resolution_query(measurement, from, to, resolution)
    |> get()
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

  def fetch_volume_with_resolution(measurement, from, to, resolution) do
    fetch_volume_with_resolution_query(measurement, from, to, resolution)
    |> get()
    |> parse_time_series()
  end

  def fetch_average_volume(measurements, from, to) when is_list(measurements) do
    fetch_average_volume_query(measurements, from, to)
    |> get()
    |> case do
      %{results: [%{series: series}]} ->
        result =
          series
          |> Enum.map(fn %{name: name, values: [[_, value]]} -> {name, value} end)

        {:ok, result}

      error ->
        {:error, error}
    end
  end

  def fetch_average_volume(measurement, from, to) do
    fetch_average_volume_query(measurement, from, to)
    |> get()
    |> parse_time_series()
  end

  def fetch_average_price(measurement, from, to) do
    fetch_average_price_query(measurement, from, to)
    |> get()
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
      fields: %{last_updated: last_updated_datetime |> DateTime.to_unix(:nanosecond)},
      tags: [ticker_cmc_id: slug],
      name: @last_history_price_cmc_measurement
    }
    |> Store.import()
  end

  def all_last_history_datetimes_cmc() do
    ~s/SELECT * FROM "#{@last_history_price_cmc_measurement}"/
    |> get()
    |> parse_time_series()
    |> case do
      {:ok, result} ->
        Enum.map(
          result,
          fn
            [_, _, _, nil] ->
              nil

            [_, timestamp_nanoseconds, _, ticker_slug] ->
              case String.split(ticker_slug, "_") do
                [_ticker, slug] -> {slug, DateTime.from_unix!(timestamp_nanoseconds, :nanosecond)}
                _ -> nil
              end
          end
        )
        |> Enum.reject(&is_nil/1)
    end
  end

  def last_history_datetime_cmc(ticker_cmc_id) do
    last_history_datetime_cmc_query(ticker_cmc_id)
    |> get()
    |> parse_time_series()
    |> case do
      {:ok, [[_, iso8601_datetime | _rest]]} ->
        {:ok, datetime} = DateTime.from_unix(iso8601_datetime, :nanosecond)
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
    |> get()
    |> parse_time_series()
  end

  def fetch_combined_mcap_volume(measurement_slugs, from, to, resolution) do
    measurement_slugs
    |> Enum.chunk_every(10)
    |> Sanbase.Parallel.map(
      fn measurements ->
        measurements = Enum.sort(measurements)

        Cache.wrap(
          fn ->
            measurements_str = measurements |> Enum.map(fn x -> ~s/"#{x}"/ end) |> Enum.join(", ")

            fetch_combined_mcap_volume_query(measurements_str, from, to, resolution)
            |> get()
          end,
          :measurements_combined_mcap_volume,
          %{measurements: measurements, from: from, to: to, resolution: resolution},
          ttl: 300,
          max_ttl_offset: 300
        ).()
      end,
      ordered: false,
      max_concurrency: 10
    )
    |> combine_results_mcap_volume()
  end

  def fetch_volume_mcap_multiple_measurements(measurement_slug_map, from, to) do
    measurement_slug_map
    |> Map.keys()
    |> Enum.chunk_every(10)
    |> Sanbase.Parallel.map(
      fn measurements ->
        measurements = Enum.sort(measurements)

        Cache.wrap(
          fn ->
            measurements_str = measurements |> Enum.map(fn x -> ~s/"#{x}"/ end) |> Enum.join(", ")

            fetch_volume_mcap_multiple_measurements_query(measurements_str, from, to)
            |> get()
          end,
          :measurements_mcap_volume,
          %{measurements: measurements, from: from, to: to},
          ttl: 300,
          max_ttl_offset: 300
        ).()
      end,
      ordered: false,
      max_concurrency: 10
    )
    |> volume_mcap_multiple_measurements_reducer(measurement_slug_map)
  end

  def fetch_volume_mcap_multiple_measurements_no_cache(measurement_slug_map, from, to) do
    measurement_slug_map
    |> Map.keys()
    |> Enum.chunk_every(10)
    |> Sanbase.Parallel.map(
      fn measurements ->
        measurements = Enum.sort(measurements)
        measurements_str = measurements |> Enum.map(fn x -> ~s/"#{x}"/ end) |> Enum.join(", ")

        fetch_volume_mcap_multiple_measurements_query(measurements_str, from, to)
        |> get()
      end,
      ordered: false,
      max_concurrency: 10
    )
    |> volume_mcap_multiple_measurements_reducer(measurement_slug_map)
  end

  def volume_over_threshold(measurements, from, to, threshold) do
    average_volume_for_period_query(measurements, from, to)
    |> get()
    |> filter_volume_over_threshold(threshold)
  end

  def first_last_price(measurement, from, to) do
    ~s/SELECT first(price_usd) as open, last(price_usd) as close
    FROM "#{measurement}"
    WHERE time >= #{influx_time(from)}
    AND time <= #{influx_time(to)}/
    |> get()
    |> parse_time_series()
  end

  def all_with_data_after_datetime(datetime) do
    datetime_unix_ns = DateTime.to_unix(datetime, :nanosecond)

    ~s/SELECT last_updated, ticker_cmc_id FROM "#{@last_history_price_cmc_measurement}"
    WHERE ticker_cmc_id != "" AND last_updated >= #{datetime_unix_ns}/
    |> get()
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
    WHERE time >= #{DateTime.to_unix(from, :nanosecond)}
    AND time <= #{DateTime.to_unix(to, :nanosecond)}/
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
     WHERE time >= #{DateTime.to_unix(from, :nanosecond)}
     AND time <= #{DateTime.to_unix(to, :nanosecond)}
     GROUP BY time(#{interval})
     FILL(0)/
  end

  defp fetch_prices_with_resolution_query(measurement, from, to, resolution) do
    ~s/SELECT LAST(price_usd), LAST(price_btc), LAST(marketcap_usd), LAST(volume_usd)
    FROM "#{measurement}"
    WHERE time >= #{DateTime.to_unix(from, :nanosecond)}
    AND time <= #{DateTime.to_unix(to, :nanosecond)}
    GROUP BY time(#{resolution}) fill(none)/
  end

  defp fetch_volume_with_resolution_query(measurement, from, to, resolution) do
    ~s/SELECT LAST(volume_usd) as volume
    FROM "#{measurement}"
    WHERE time >= #{DateTime.to_unix(from, :nanosecond)}
    AND time <= #{DateTime.to_unix(to, :nanosecond)}
    GROUP BY time(#{resolution}) fill(none)/
  end

  defp fetch_last_price_point_before_query(measurement, timestamp) do
    ~s/SELECT LAST(price_usd), price_btc, marketcap_usd, volume_usd
    FROM "#{measurement}"
    WHERE time <= #{DateTime.to_unix(timestamp, :nanosecond)}/
  end

  defp fetch_average_volume_query(measurements, from, to) do
    measurements_str =
      measurements |> List.wrap() |> Enum.map(fn x -> ~s/"#{x}"/ end) |> Enum.join(", ")

    ~s/SELECT MEAN(volume_usd)
    FROM #{measurements_str}
    WHERE time >= #{DateTime.to_unix(from, :nanosecond)}
    AND time <= #{DateTime.to_unix(to, :nanosecond)}/
  end

  defp fetch_average_price_query(measurement, from, to) do
    ~s/SELECT MEAN(price_usd), MEAN(price_btc)
    FROM "#{measurement}"
    WHERE time >= #{DateTime.to_unix(from, :nanosecond)}
    AND time <= #{DateTime.to_unix(to, :nanosecond)}/
  end

  defp last_history_datetime_cmc_query(ticker_cmc_id) do
    ~s/SELECT * FROM "#{@last_history_price_cmc_measurement}"
    WHERE ticker_cmc_id = '#{ticker_cmc_id}'/
  end

  defp fetch_volume_mcap_multiple_measurements_query(measurements_str, from, to) do
    ~s/SELECT LAST(volume_usd), LAST(marketcap_usd)
      FROM #{measurements_str}
      WHERE time >= #{DateTime.to_unix(from, :nanosecond)}
      AND time <= #{DateTime.to_unix(to, :nanosecond)}/
  end

  defp fetch_combined_mcap_volume_query(measurements_str, from, to, resolution) do
    ~s/SELECT LAST(volume_usd), LAST(marketcap_usd)
       FROM #{measurements_str}
       WHERE time >= #{DateTime.to_unix(from, :nanosecond)}
       AND time <= #{DateTime.to_unix(to, :nanosecond)}
       GROUP BY time(#{resolution}) fill(0)/
  end

  defp volume_mcap_multiple_measurements_reducer(results, measurement_slug_map) do
    result = combine_results(results)

    case result do
      %{errors: [], series: series} ->
        slugs = series |> Enum.map(fn s -> measurement_slug_map[s.name] end)
        values = series |> Enum.map(& &1.values)
        volume_values = values |> Enum.map(fn [[_, vol, _]] -> vol end)
        combined_mcap = values |> Enum.reduce(0, fn [[_, _, mcap]], acc -> acc + mcap end)
        marketcap_values = values |> Enum.map(fn [[_, _, mcap]] -> mcap end)

        marketcap_percent =
          marketcap_values |> Enum.map(fn mcap -> Float.round(mcap / combined_mcap, 5) end)

        data = Enum.zip([slugs, volume_values, marketcap_values, marketcap_percent])

        {:ok, data}

      %{errors: [error | _]} ->
        {:error, error}
    end
  end

  defp combine_results_mcap_volume(results) do
    %{series: series, errors: errors} = combine_results(results)

    case errors do
      [] ->
        :ok

      _ ->
        Logger.warn(
          "Encountered errors while fetching combined marketcap and volume: #{inspect(errors)}"
        )
    end

    data =
      series
      |> Enum.map(fn %{values: values} -> values end)
      |> Enum.zip()
      |> Stream.map(&Tuple.to_list/1)
      |> Enum.map(fn [[iso8601_datetime, _, _] | _] = projects_data ->
        {:ok, datetime, _} = DateTime.from_iso8601(iso8601_datetime)

        {combined_volume, combined_mcap} =
          projects_data
          |> Enum.reduce({0, 0}, fn [_, volume, mcap], {v, m} -> {v + volume, m + mcap} end)

        %{datetime: datetime, volume: combined_volume, marketcap: combined_mcap}
      end)

    {:ok, data}
  end

  defp combine_results(results) when is_list(results) do
    Enum.reduce(results, %{errors: [], series: []}, fn
      %{results: [%{series: series}]}, acc -> %{acc | series: series ++ acc.series}
      %{results: [%{error: error}]}, acc -> %{acc | errors: [error | acc.errors]}
      _, acc -> %{acc | errors: [:error | acc.errors]}
    end)
  end

  defp average_volume_for_period_query(measurements, from, to) do
    ~s/SELECT MEAN(volume_usd) as volume
    FROM #{measurements}
    WHERE time >= #{DateTime.to_unix(from, :nanosecond)}
    AND time <= #{DateTime.to_unix(to, :nanosecond)}/
  end
end
