defmodule Sanbase.Etherbi.TransactionVolume.Store do
  use Sanbase.Influxdb.Store

  alias Sanbase.Etherbi.TransactionVolume.Store

  def transaction_volume(measurement, from, to, resolution) do
    transaction_volume_from_to_query(measurement, from, to, resolution)
    |> Store.query()
    |> parse_transaction_volume_time_series()
  end

  def transaction_volume!(measurement, from, to, resolution) do
    case transaction_volume(measurement, from, to, resolution) do
      {:ok, result} -> result
      {:error, error} -> raise(error)
    end
  end

  # Private functions

  defp transaction_volume_from_to_query(measurement, from, to, resolution) do
    ~s/SELECT SUM(transaction_volume)
    FROM "#{measurement}"
    WHERE time >= #{DateTime.to_unix(from, :nanoseconds)}
    AND time <= #{DateTime.to_unix(to, :nanoseconds)}
    GROUP BY time(#{resolution}) fill(none)/
  end

  defp parse_transaction_volume_time_series(%{error: error}) do
    {:error, error}
  end

  defp parse_transaction_volume_time_series(%{results: [%{error: error}]}) do
    {:error, error}
  end

  defp parse_transaction_volume_time_series(%{
         results: [
           %{
             series: [
               %{
                 values: transaction_volume
               }
             ]
           }
         ]
       }) do
    result =
      transaction_volume
      |> Enum.map(fn [iso8601_datetime, trx_volume] ->
        {:ok, datetime, _} = DateTime.from_iso8601(iso8601_datetime)
        {datetime, trx_volume}
      end)

    {:ok, result}
  end

  defp parse_transaction_volume_time_series(_) do
    {:ok, []}
  end
end