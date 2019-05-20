defmodule Sanbase.Clickhouse.GasUsed do
  @moduledoc ~s"""
  Uses ClickHouse to calculate used gas.
  """

  import Sanbase.Math, only: [to_integer: 1]
  alias Sanbase.DateTimeUtils
  require Sanbase.ClickhouseRepo, as: ClickhouseRepo

  @type gas_used :: %{
          datetime: DateTime.t(),
          eth_gas_used: non_neg_integer()
        }

  @spec gas_used(
          String.t(),
          DateTime.t(),
          DateTime.t(),
          String.t()
        ) :: {:ok, list(gas_used)} | {:error, String.t()}
  def gas_used("ethereum", from, to, interval) do
    {query, args} = gas_used_query(from, to, interval)

    ClickhouseRepo.query_transform(
      query,
      args,
      fn [dt, gas_used] ->
        %{
          datetime: DateTime.from_unix!(dt),
          eth_gas_used: gas_used |> to_integer()
        }
      end
    )
  end

  def gas_used(_, _, _, _), do: {:error, "Currently only ethereum is supported!"}

  defp gas_used_query(from, to, interval) do
    from_datetime_unix = DateTime.to_unix(from)
    to_datetime_unix = DateTime.to_unix(to)
    interval = DateTimeUtils.compound_duration_to_seconds(interval)

    query = """
    SELECT
      toUnixTimestamp(intDiv(toUInt32(toDateTime(dt)), ?1) * ?1) AS time,
      sum(gasUsed) AS gas_used
    FROM eth_blocks
    PREWHERE
      dt >= toDateTime(?2) AND
      dt <= toDateTime(?3)
    GROUP BY time
    ORDER BY time ASC
    """

    args = [interval, from_datetime_unix, to_datetime_unix]

    {query, args}
  end
end
