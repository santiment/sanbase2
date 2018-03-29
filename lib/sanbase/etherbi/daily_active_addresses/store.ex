defmodule Sanbase.Etherbi.DailyActiveAddresses.Store do
  @moduledoc ~S"""
    Module with functions for working with Daily Active Users
  """

  use Sanbase.Influxdb.Store
  alias __MODULE__

  def daily_active_addresses(measurement, from, to, interval) do
    daily_active_addresses_query(measurement, from, to, interval)
    |> Store.query()
    |> parse_time_series()
  end

  # Private functions

  defp daily_active_addresses_query(measurement, from, to, "1d") do
    ~s/SELECT active_addresses FROM "#{measurement}"
    WHERE time >= #{influx_time(from)}
    AND time <= #{influx_time(to)}/
  end

  defp daily_active_addresses_query(measurement, from, to, interval) do
    ~s/SELECT MEAN(active_addresses) FROM "#{measurement}"
    WHERE time >= #{influx_time(from)}
    AND time <= #{influx_time(to)}
    GROUP BY time(#{interval}) fill(0)/
  end
end
