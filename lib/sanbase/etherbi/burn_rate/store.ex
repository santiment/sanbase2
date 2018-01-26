defmodule Sanbase.Etherbi.BurnRate.Store do
  use Sanbase.Influxdb.Store

  alias Sanbase.Etherbi.BurnRate.Store

  def burn_rate(measurement, from, to, resolution) do
    burn_rate_from_to_query(measurement, from, to, resolution)
    |> Store.query()
    |> parse_burn_rate_time_series()
  end

  def burn_rate!(measurement, from, to, resolution) do
    case burn_rate(measurement, from, to, resolution) do
      {:ok, result} -> result
      {:error, error} -> raise(error)
    end
  end

  # Private functions

  defp burn_rate_from_to_query(measurement, from, to, resolution) do
    ~s/SELECT burn_rate
    FROM "#{measurement}"
    AND time >= #{DateTime.to_unix(from, :nanoseconds)}
    AND time <= #{DateTime.to_unix(to, :nanoseconds)}
    GROUP BY time(#{resolution}) fill(none/
  end

  defp parse_burn_rate_time_series(%{error: error}) do
    {:error, error}
  end

  defp parse_burn_rate_time_series(%{results: [%{error: error}]}) do
    {:error, error}
  end

  defp parse_burn_rate_time_series(%{
         results: [
           %{
             series: [
               %{
                 values: burn_rate
               }
             ]
           }
         ]
       }) do
    result =
    burn_rate
      |> Enum.map(fn [iso8601_datetime, burn_rate] ->
        {:ok, datetime, _} = DateTime.from_iso8601(iso8601_datetime)
        {datetime, burn_rate}
      end)

    {:ok, result}
  end

  defp parse_transactions_time_series(_) do
    {:ok, []}
  end
end