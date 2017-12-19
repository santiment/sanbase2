defmodule Sanbase.Github.Store do
  # A module for storing and fetching github activity data from/to a time series data store
  #
  # Currently using InfluxDB for the time series data.
  use Instream.Connection, otp_app: :sanbase

  alias Sanbase.Github.Measurement
  alias Sanbase.Github.Store

  def import(measurements) do
    measurements
    |> Stream.map(&convert_measurement_for_import/1)
    |> Stream.chunk_every(288) # 1 day of 5 min resolution data
    |> Enum.map(fn data_for_import ->
      :ok = Store.write(data_for_import)
    end)
  end

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

  def first_activity_datetime(ticker) do
    ~s/SELECT FIRST(activity) FROM "#{ticker}"/
    |> Store.query()
    |> parse_measurement_datetime
  end

  def last_activity_datetime(ticker) do
    ~s/SELECT LAST(activity) FROM "#{ticker}"/
    |> Store.query()
    |> parse_measurement_datetime
  end

  defp parse_measurement_datetime(%{
    results: [%{
      series: [%{
        values: [[iso8601_datetime, _price]]
      }]
    }]
  }) do
    {:ok, datetime, _} = DateTime.from_iso8601(iso8601_datetime)

    datetime
  end

  defp parse_measurement_datetime(_), do: nil

  def drop_ticker(ticker) do
    %{results: _} = "DROP MEASUREMENT #{ticker}"
    |> Store.execute()
  end

  def create_db() do
    database()
    |> Instream.Admin.Database.create()
    |> Store.execute()
  end

  defp database() do
    Application.fetch_env!(:sanbase, Sanbase.Github.Store)
    |> Keyword.get(:database)
  end
end
