defmodule Sanbase.Etherbi.Store do
  use Sanbase.Influxdb.Store

  alias Sanbase.Influxdb.Measurement
  alias Sanbase.Etherbi.Store

  def last_datetime(measurement) do
    ~s/SELECT LAST(*) FROM "#{measurement}"/
    |> Store.query()
    |> parse_measurement_datetime()
  end

  def last_datetime_with_tag(measurement, tag_name, tag_value) when is_binary(tag_value) do
    ~s/SELECT LAST(*) FROM "#{measurement}"
    WHERE "#{tag_name}" = "#{tag_value}"/
    |> Store.query()
    |> parse_measurement_datetime()
  end

  def last_datetime_with_tag(measurement, tag_name, tag_value) do
    ~s/SELECT LAST(*) FROM "#{measurement}"
    WHERE "#{tag_name}" = #{tag_value}/
    |> Store.query()
    |> parse_measurement_datetime()
  end

  def first_datetime(measurement) do
    ~s/SELECT FIRST(*) FROM "#{measurement}"/
    |> Store.query()
    |> parse_measurement_datetime()
  end

  def transactions(measurement, from, to, transaction_type) do
    transactions_from_to_query(measurement, from, to, transaction_type)
    |> Store.query()
    |> parse_transactions_time_series()
  end

  defp transactions_from_to_query(measurement, from, to, "all") do
    ~s/SELECT volume, address
    FROM "#{measurement}"
    WHERE time >= #{DateTime.to_unix(from, :nanoseconds)}
    AND time <= #{DateTime.to_unix(to, :nanoseconds)}/
  end

  defp transactions_from_to_query(measurement, from, to, transaction_type) do
    ~s/SELECT volume, address
    FROM "#{measurement}"
    WHERE transaction_type = '#{transaction_type}'
    AND time >= #{DateTime.to_unix(from, :nanoseconds)}
    AND time <= #{DateTime.to_unix(to, :nanoseconds)}/
  end

  defp parse_transactions_time_series(%{error: error}) do
    {:error, error}
  end

  defp parse_transactions_time_series(%{results: [%{error: error}]}) do
    {:error, error}
  end

  defp parse_transactions_time_series(%{
         results: [
           %{
             series: [
               %{
                 values: transactions
               }
             ]
           }
         ]
       }) do
    result =
      transactions
      |> Enum.map(fn [iso8601_datetime, volume, address] ->
        {:ok, datetime, _} = DateTime.from_iso8601(iso8601_datetime)
        {datetime, volume, address}
      end)

    {:ok, result}
  end

  defp parse_transactions_time_series(_) do
    {:ok, []}
  end

  defp parse_measurement_datetime(%{results: [%{error: error}]}) do
    {:error, error}
  end

  defp parse_measurement_datetime(%{
         results: [
           %{
             series: [
               %{
                 values: [iso8601_datetime | _rest]
               }
             ]
           }
         ]
       }) do
    {:ok, datetime, _} = DateTime.from_iso8601(iso8601_datetime)

    {:ok, datetime}
  end

  defp parse_measurement_datetime(_) do
    {:ok, nil}
  end
end