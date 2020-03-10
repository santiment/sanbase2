defmodule Sanbase.Twitter.Store do
  @moduledoc ~S"""
    A module for storing and fetching twitter account data from a time series data store
  """

  use Sanbase.Influxdb.Store

  alias Sanbase.Influxdb.Measurement
  alias Sanbase.Twitter.Store

  def all_records_for_measurement(measurement_name, from, to, interval) do
    select_from_to_query(measurement_name, from, to, interval)
    |> get()
    |> parse_twitter_data_series()
  end

  def all_records_for_measurement!(measurement_name, from, to, interval) do
    case all_records_for_measurement(measurement_name, from, to, interval) do
      {:ok, result} -> result
      {:error, error} -> raise(error)
    end
  end

  def last_record_for_measurement(measurement_name) do
    select_last_record_query(measurement_name)
    |> get()
    |> parse_twitter_record()
  end

  def last_record_with_tag_value(measurement_name, tag_name, tag_value) do
    ~s/SELECT LAST(followers_count) FROM "#{measurement_name}"
    WHERE #{tag_name} = '#{tag_value}'/
    |> Store.execute()
    |> parse_twitter_record()
  end

  defp select_from_to_query(measurement_name, from, to, interval) do
    ~s/SELECT time, LAST(followers_count)
    FROM "#{measurement_name}"
    WHERE time >= #{DateTime.to_unix(from, :nanosecond)}
    AND time <= #{DateTime.to_unix(to, :nanosecond)}
    GROUP BY time(#{interval}) fill(none)/
  end

  defp select_last_record_query(measurement_name) do
    ~s/SELECT LAST(followers_count) FROM "#{measurement_name}"/
  end

  defp parse_twitter_data_series(%{results: [%{error: error}]}), do: {:error, error}

  defp parse_twitter_data_series(%{
         results: [
           %{
             series: [
               %{
                 values: twitter_data_series
               }
             ]
           }
         ]
       }) do
    result =
      twitter_data_series
      |> Enum.map(fn [iso8601_datetime, followers_count] ->
        {:ok, datetime, _} = DateTime.from_iso8601(iso8601_datetime)
        {datetime, followers_count}
      end)

    {:ok, result}
  end

  defp parse_twitter_data_series(_), do: {:ok, []}

  defp parse_twitter_record(%{
         results: [
           %{
             series: [
               %{
                 values: [[iso8601_datetime, followers_count]]
               }
             ]
           }
         ]
       }) do
    {:ok, datetime, _} = DateTime.from_iso8601(iso8601_datetime)

    {datetime, followers_count}
  end

  defp parse_twitter_record(_), do: nil
end
