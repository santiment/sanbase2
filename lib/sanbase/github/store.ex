defmodule Sanbase.Github.Store do
  # A module for storing and fetching github activity data from/to a time series data store
  #
  # Currently using InfluxDB for the time series data.
  use Sanbase.Influxdb.Store

  alias Sanbase.Influxdb.Measurement
  alias Sanbase.Github.Store

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
         results: [
           %{
             series: [
               %{
                 values: [[iso8601_datetime, _price]]
               }
             ]
           }
         ]
       }) do
    {:ok, datetime, _} = DateTime.from_iso8601(iso8601_datetime)

    datetime
  end

  defp parse_measurement_datetime(_), do: nil
end