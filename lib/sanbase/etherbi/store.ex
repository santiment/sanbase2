defmodule Sanbase.Etherbi.Store do
  use Sanbase.Influxdb.Store
  alias Sanbase.Influxdb.Measurement
  alias Sanbase.Github.Store

  def last_datetime(measurement) do
    ~s/SELECT LAST(*) FROM "#{measurement}"/
    |> Store.query()
    |> parse_measurement_datetime()
  end

  def first_datetime(measurement) do
    ~s/SELECT FIRST(*) FROM "#{measurement}"/
    |> Store.query()
    |> parse_measurement_datetime()
  end

  defp parse_measurement_datetime(%{
         results: [
           %{
             series: [
               %{
                 values: [[iso8601_datetime | _rest]]
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