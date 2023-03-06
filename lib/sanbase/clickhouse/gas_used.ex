defmodule Sanbase.Clickhouse.GasUsed do
  @moduledoc ~s"""
  Uses ClickHouse to calculate used gas.
  """

  import Sanbase.Math, only: [to_integer: 1]
  alias Sanbase.DateTimeUtils
  alias Sanbase.ClickhouseRepo

  @type gas_used :: %{
          datetime: DateTime.t(),
          eth_gas_used: non_neg_integer(),
          gas_used: non_neg_integer()
        }

  @spec gas_used(
          String.t(),
          DateTime.t(),
          DateTime.t(),
          String.t()
        ) :: {:ok, list(gas_used)} | {:error, String.t()}
  def gas_used("ethereum", from, to, interval) do
    query_struct = gas_used_query(from, to, interval)

    ClickhouseRepo.query_transform(
      query_struct,
      fn [dt, gas_used] ->
        %{
          datetime: DateTime.from_unix!(dt),
          gas_used: gas_used |> to_integer(),
          eth_gas_used: gas_used |> to_integer()
        }
      end
    )
  end

  def gas_used(_, _, _, _), do: {:error, "Currently only ethereum is supported!"}

  defp gas_used_query(from, to, interval) do
    sql = """
    SELECT
      toUnixTimestamp(intDiv(toUInt32(toDateTime(dt)), {{interval}}) * {{interval}}) AS time,
      sum(gasUsed) AS gas_used
    FROM eth_blocks
    PREWHERE
      dt >= toDateTime({{from}}) AND
      dt < toDateTime({{to}})
    GROUP BY time
    ORDER BY time ASC
    """

    params = %{
      interval: DateTimeUtils.str_to_sec(interval),
      from: DateTime.to_unix(from),
      to: DateTime.to_unix(to)
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end
end
