defmodule Sanbase.ExternalServices.TwitterData.Store do
  @moduledoc ~S"""
    A module for storing and fetching twitter account data from a time series data store
  """

  use Sanbase.Influxdb.Store

  alias Sanbase.Influxdb.Measurement
  alias Sanbase.ExternalServices.TwitterData.Store

  def all_records_for_measurement(measurement_name, from, to) do
    select_from_to_query(measurement_name, from, to)
    |> Store.query()
    |> parse_twitter_data_series()
  end

  def last_record_for_measurement(measurement_name) do
    select_last_record_query(measurement_name)
    |> Store.query()
    |> parse_twitter_record()
  end

  def last_record_with_tag_value(measurement_name, tag_name, tag_value) do
    ~s/SELECT LAST(followers_count) FROM "#{measurement_name}"
    WHERE #{tag_name} = '#{tag_value}'/
    |> Store.execute()
    |> parse_twitter_record()
  end

  defp select_from_to_query(measurement_name, from, to) do
    ~s/SELECT time, followers_count
    FROM "#{measurement_name}"
    WHERE time >= #{DateTime.to_unix(from, :nanoseconds)}
    AND time <= #{DateTime.to_unix(to, :nanoseconds)}/
  end

  defp select_last_tag_value_query(measurement_name, tag_name, tag_value) when is_bitstring(tag_value) do
    ~s/SELECT LAST(followers_count) FROM "#{measurement_name}"
    WHERE #{tag_name} = '#{tag_value}'/
  end

  defp select_last_tag_value_query(measurement_name, tag_name, tag_value) when is_integer(tag_value) do
    ~s/SELECT LAST(followers_count) FROM "#{measurement_name}"
    WHERE #{tag_name} = #{tag_value}/
  end

  defp select_last_record_query(measurement_name) do
    ~s/SELECT LAST(followers_count) FROM "#{measurement_name}"/
  end

  defp parse_twitter_data_series(%{results: [%{error: error}]}), do: raise(error)

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
    twitter_data_series
    |> Enum.map(fn [iso8601_datetime, followers_count] ->
         {:ok, datetime, _} = DateTime.from_iso8601(iso8601_datetime)
         {datetime, followers_count}
       end)
  end

  defp parse_twitter_data_series(_), do: []

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
