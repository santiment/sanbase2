defmodule Sanbase.Clickhouse.HistoricalBalance.MinersBalance do
  @moduledoc ~s"""
  Uses ClickHouse to calculate miner balances over time.
  """

  import Sanbase.DateTimeUtils, only: [str_to_sec: 1]
  require Sanbase.ClickhouseRepo, as: ClickhouseRepo

  @table "eth_miners_metrics"
  @miners_balance_id 102

  @type balance :: %{datetime: DateTime.t(), balance: number()}

  @spec historical_balance(
          String.t(),
          DateTime.t(),
          DateTime.t(),
          String.t()
        ) :: {:ok, list(balance)} | {:error, String.t()}
  def historical_balance("ethereum", from, to, interval) do
    {query, args} = balances_query(from, to, interval)

    ClickhouseRepo.query_transform(
      query,
      args,
      fn [timestamp, balance] ->
        %{
          datetime: DateTime.from_unix!(timestamp),
          balance: balance
        }
      end
    )
  end

  def historical_balance(_, _, _, _), do: {:error, "Currently only ethereum is supported!"}

  def first_datetime(_), do: ~U[2015-07-30 00:00:00Z]

  defp balances_query(from, to, interval) do
    query = """
    SELECT
      toUnixTimestamp((intDiv(toUInt32(toDateTime(dt)), ?1) * ?1)) AS ts,
      anyLast(balance)
    FROM (
      SELECT
        dt,
        value AS balance
      FROM (
        SELECT
          days,
          arrayCumSum(values) AS values
        FROM (
          SELECT
            groupArray(dt) AS days,
            groupArray(value) AS values
          FROM (
            SELECT
              toDateTime(date) AS dt,
              argMax(value, calculation_date) AS value
            FROM #{@table}
            WHERE
              id = #{@miners_balance_id} AND
              date <= toDate(?3)
            GROUP BY dt, date
            ORDER BY dt
          )
        )
      )
      ARRAY JOIN
        days AS dt,
        values AS value
      WHERE
        dt >= ?2 AND
        dt <= ?3
      )
    GROUP BY ts
    ORDER BY ts
    """

    args = [
      interval |> str_to_sec(),
      from |> DateTime.to_unix(),
      to |> DateTime.to_unix()
    ]

    {query, args}
  end
end
