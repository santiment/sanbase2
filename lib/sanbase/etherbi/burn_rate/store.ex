defmodule Sanbase.Etherbi.BurnRate.Store do
  @moduledoc ~S"""
    Module with functions for working with burn rate influx database
  """
  use Sanbase.Influxdb.Store

  alias Sanbase.Etherbi.BurnRate.Store

  @doc ~S"""
    Get the burn rate for a given ticker and time period.
    Returns a tuple `{:ok, result}` on success, `{:error, error}` otherwise
  """
  @spec burn_rate(binary(), %DateTime{}, %DateTime{}, binary()) :: {:ok, list()} | {:error, binary()}
  def burn_rate(measurement, from, to, resolution) do
    burn_rate_from_to_query(measurement, from, to, resolution)
    |> Store.query()
    |> parse_burn_rate_time_series()
  end

  @doc ~S"""
    Get the burn rate for a given ticker and time period.
    Retunrs `result` on success, raises and error otherwise
  """
  @spec burn_rate!(binary(), %DateTime{}, %DateTime{}, binary()) :: list() | no_return()
  def burn_rate!(measurement, from, to, resolution) do
    case burn_rate(measurement, from, to, resolution) do
      {:ok, result} -> result
      {:error, error} -> raise(error)
    end
  end

  # Private functions

  defp burn_rate_from_to_query(measurement, from, to, resolution) do
    ~s/SELECT SUM(burn_rate)
    FROM "#{measurement}"
    WHERE time >= #{DateTime.to_unix(from, :nanoseconds)}
    AND time <= #{DateTime.to_unix(to, :nanoseconds)}
    GROUP BY time(#{resolution}) fill(none)/
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

  defp parse_burn_rate_time_series(_) do
    {:ok, []}
  end
end