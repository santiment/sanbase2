defmodule Sanbase.Github.Store do
  @moduledoc """
  A module for storing and fetching github activity data from/to a time series data store
  InfluxDB is used for the timeseries databae
  """
  use Sanbase.Influxdb.Store

  alias Sanbase.Influxdb.Measurement
  alias Sanbase.Github.Store

  def first_activity_datetime(ticker) do
    ~s/SELECT FIRST(activity) FROM "#{ticker}"/
    |> Store.query()
    |> parse_measurement_datetime()
  end

  def last_activity_datetime(ticker) do
    ~s/SELECT LAST(activity) FROM "#{ticker}"/
    |> Store.query()
    |> parse_measurement_datetime()
  end

  def fetch_activity_with_resolution!(repo, from, to, resolution) do
    activity_with_resolution_query(repo, from, to, resolution)
    |> Store.query()
    |> parse_activity_series!()
  end

  defp activity_with_resolution_query(repo, from, to, resolution) do
    ~s/SELECT SUM(activity)
    FROM "#{repo}"
    WHERE time >= #{DateTime.to_unix(from, :nanoseconds)}
    AND time <= #{DateTime.to_unix(to, :nanoseconds)}
    GROUP BY time(#{resolution}) fill(none)/
  end

  defp parse_activity_series!(%{results: [%{error: error}]}), do: raise(error)

  defp parse_activity_series!(%{
         results: [
           %{
             series: [
               %{
                 values: activity_series
               }
             ]
           }
         ]
       }) do
    activity_series
    |> Enum.map(fn [iso8601_datetime, activity] ->
         {:ok, datetime, _} = DateTime.from_iso8601(iso8601_datetime)
         {datetime, activity}
       end)
  end

  defp parse_measurement_datetime(%{
         results: [
           %{
             series: [
               %{
                 values: [[iso8601_datetime, _activity]]
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