defmodule Sanbase.Prices.Store do
  # A module for storing and fetching pricing data from a time series data store
  #
  # Currently using InfluxDB for the time series data.
  #
  # There is a single database at the moment, which contains simple average
  # price data for a given currency pair within a given interval. The current
  # interval is about 5 mins (+/- 3 seconds). The timestamps are stores as
  # nanoseconds
  use Instream.Connection, otp_app: :sanbase

  alias Sanbase.Prices.Store
  alias Sanbase.Prices.Measurement

  def import(measurements) do
    measurements
    |> Stream.map(&convert_measurement_for_import/1)
    |> Stream.chunk_every(288) # 1 day of 5 min resolution data
    |> Enum.map(fn data_for_import ->
      :ok = Store.write(data_for_import, database: price_database())
    end)
  end

  def fetch_price_points(pair, from, to) do
    fetch_query(pair, from, to)
    |> q()
  end

  def fetch_prices_with_resolution(pair, from, to, resolution) do
    ~s/SELECT MEAN(price), SUM(volume), MEAN(marketcap)
    FROM "#{pair}"
    WHERE time >= #{DateTime.to_unix(from, :nanoseconds)} AND time <= #{DateTime.to_unix(to, :nanoseconds)}
    GROUP BY time(#{resolution})/
    |> q()
  end

  def q(query) do
    Store.query(query, database: price_database())
    |> parse_price_series
  end

  defp fetch_query(pair, from, to) do
    ~s/SELECT time, price, volume, marketcap
    FROM "#{pair}"
    WHERE time >= #{DateTime.to_unix(from, :nanoseconds)} AND time <= #{DateTime.to_unix(to, :nanoseconds)}/
  end

  defp parse_price_series(%{results: [%{error: error}]}), do: raise error

  defp parse_price_series(%{
    results: [%{
      series: [%{
        values: price_series
      }]
    }]
  }) do
    price_series
    |> Enum.map(fn [iso8601_datetime | tail] ->
      {:ok, datetime, _} = DateTime.from_iso8601(iso8601_datetime)
      [datetime | tail]
    end)
  end

  defp parse_price_series(_), do: []

  def last_price_datetime(pair) do
    ~s/SELECT time, price FROM "#{pair}" ORDER BY time DESC LIMIT 1/
    |> Store.query(database: price_database())
    |> parse_last_price_datetime
  end

  defp parse_last_price_datetime(%{
    results: [%{
      series: [%{
        values: [[iso8601_datetime, _price]]
      }]
    }]
  }) do
    {:ok, datetime, _} = DateTime.from_iso8601(iso8601_datetime)

    datetime
  end

  defp parse_last_price_datetime(_), do: nil

  defp convert_measurement_for_import(%Measurement{timestamp: timestamp, fields: fields, tags: tags, name: name}) do
    %{
      points: [%{
        measurement: name,
        fields: fields,
        tags: tags || [],
        timestamp: timestamp
      }]
    }
  end

  def drop_pair(pair) do
    %{results: _} = "DROP MEASUREMENT #{pair}"
    |> Store.execute(database: price_database())
  end

  defp price_database() do
    Application.fetch_env!(:sanbase, Sanbase.ExternalServices.Coinmarketcap)
    |> Keyword.get(:database)
  end
end
