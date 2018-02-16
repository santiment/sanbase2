defmodule Sanbase.Github.Store do
  @moduledoc """
  A module for storing and fetching github activity data from/to a time series data store
  InfluxDB is used for the timeseries databae
  """
  use Sanbase.Influxdb.Store

  alias Sanbase.Influxdb.Measurement
  alias Sanbase.Github.Store

  def fetch_activity_with_resolution!(ticker, from, to, resolution) do
    activity_with_resolution_query(ticker, from, to, resolution)
    |> Store.query()
    |> parse_activity_series!()
  end

  def fetch_moving_average_for_hours!(ticker, from, to, interval, ma_interval) do
    moving_average_activity(ticker, from, to, interval, ma_interval)
    |> Store.query()
    |> parse_moving_average_series!()
  end

  def fetch_total_activity(ticker, from, to) do
    total_activity_query(ticker, from, to)
    |> Store.query()
    |> parse_activity_series()
    |> case do
      {:ok, []} ->
        {:ok, nil}

      {:ok, [result]} ->
        {:ok, result}

      result ->
        result
    end
  end

  # The subsequent fields are 1 hour apart, so the interval must be in hours
  defp moving_average_activity(ticker, from, to, interval, ma_interval) do
    ~s/SELECT MOVING_AVERAGE(SUM(activity), #{ma_interval})
    FROM "#{ticker}"
    WHERE time >= #{DateTime.to_unix(from, :nanoseconds)}
    AND time <= #{DateTime.to_unix(to, :nanoseconds)}
    GROUP BY time(#{interval}) fill(0)/
  end

  defp total_activity_query(ticker, from, to) do
    ~s/SELECT SUM(activity)
    FROM "#{ticker}"
    WHERE time >= #{DateTime.to_unix(from, :nanoseconds)}
    AND time <= #{DateTime.to_unix(to, :nanoseconds)}/
  end

  defp activity_with_resolution_query(ticker, from, to, resolution) do
    ~s/SELECT SUM(activity)
    FROM "#{ticker}"
    WHERE time >= #{DateTime.to_unix(from, :nanoseconds)}
    AND time <= #{DateTime.to_unix(to, :nanoseconds)}
    GROUP BY time(#{resolution}) fill(none)/
  end

  defp parse_activity_series!(result) do
    case parse_activity_series(result) do
      {:ok, result} ->
        result

      {:error, error} ->
        raise(error)
    end
  end

  defp parse_activity_series(%{
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
    result =
      activity_series
      |> Enum.map(fn [iso8601_datetime, activity] ->
        {:ok, datetime, _} = DateTime.from_iso8601(iso8601_datetime)
        {datetime, activity}
      end)

    {:ok, result}
  end

  defp parse_activity_series(%{results: [%{error: error}]}), do: {:error, error}

  defp parse_activity_series(%{
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
    result =
      activity_series
      |> Enum.map(fn [iso8601_datetime, activity] ->
        {:ok, datetime, _} = DateTime.from_iso8601(iso8601_datetime)
        {datetime, activity}
      end)

    {:ok, result}
  end

  defp parse_activity_series(_), do: {:ok, []}

  defp parse_moving_average_series!(%{results: [%{error: error}]}), do: raise(error)

  defp parse_moving_average_series!(%{
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

      activity =
        if is_float(activity) do
          activity |> Float.ceil() |> Kernel.trunc()
        else
          activity
        end

      {datetime, activity}
    end)
  end

  defp parse_moving_average_series!(_), do: []
end
