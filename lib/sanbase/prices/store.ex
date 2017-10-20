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
  alias Sanbase.Prices.Point

  @price_database "prices"

  def import_price_points(price_points, pair, tags) do
    price_points
    |> Stream.map(&convert_to_price_series(&1, pair, tags))
    |> Stream.chunk_every(300) # About 1 day of 5 min resolution data
    |> Enum.map(&Store.write(&1, database: @price_database))
  end

  def fetch_price_points(pair, from, to) do
    fetch_query(pair, from, to)
    |> Store.query(database: @price_database)
  end

  def last_price_datetime(pair) do
    "SELECT time, price FROM #{pair} ORDER BY time DESC LIMIT 1"
    |> Store.query(database: @price_database)
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

  defp parse_last_price_datetime(result), do: IO.inspect(result)

  defp fetch_query(pair, from, to) do
    "SELECT time, price, volume, marketcap
    FROM #{pair}
    WHERE time >= #{DateTime.to_unix(from, :nanoseconds)} AND time <= #{DateTime.to_unix(to, :nanoseconds)}"
  end

  defp convert_to_price_series(%Point{datetime: datetime, price: price, volume: volume, marketcap: marketcap}, pair, tags) do
    %{
      points: [%{
        measurement: pair,
        fields: %{
          price: price,
          volume: volume,
          marketcap: marketcap,
        },
        tags: tags,
        timestamp: DateTime.to_unix(datetime, :nanosecond)
      }]
    }
  end
end
