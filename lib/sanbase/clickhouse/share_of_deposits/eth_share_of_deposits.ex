defmodule Sanbase.Clickhouse.EthShareOfDeposits do
  @moduledoc ~s"""
  Uses ClickHouse to calculate share of deposits from daily active addresses for ETH
  """

  require Sanbase.ClickhouseRepo, as: ClickhouseRepo
  import Sanbase.Math, only: [to_integer: 1]

  alias Sanbase.DateTimeUtils

  @type share_of_deposits :: %{
          datetime: %DateTime{},
          active_addresses: non_neg_integer(),
          active_deposits: non_neg_integer(),
          share_of_deposits: number()
        }

  @spec share_of_deposits(
          %DateTime{},
          %DateTime{},
          String.t()
        ) :: {:ok, list(share_of_deposits)} | {:error, String.t()}
  def share_of_deposits(from, to, interval) do
    {query, args} = share_of_deposits_query(from, to, interval)

    ClickhouseRepo.query_transform(
      query,
      args,
      fn [dt, active_addresses, active_deposits, share_of_deposits] ->
        %{
          datetime: DateTime.from_unix!(dt),
          active_addresses: active_addresses |> to_integer(),
          active_deposits: active_deposits |> to_integer(),
          share_of_deposits: share_of_deposits
        }
      end
    )
  end

  defp share_of_deposits_query(from, to, interval) do
    interval = DateTimeUtils.compound_duration_to_seconds(interval)
    from_datetime_unix = DateTime.to_unix(from)
    to_datetime_unix = DateTime.to_unix(to)
    span = div(to_datetime_unix - from_datetime_unix, interval) |> max(1)

    query = """
    SELECT
      toUnixTimestamp(time) AS dt,
      SUM(addresses) AS active_addresses,
      SUM(deposits) AS active_deposits,
      if(SUM(addresses) != 0, SUM(deposits)/SUM(addresses), 0) * 100 AS share_of_deposits
    FROM (
      SELECT
        toDateTime(intDiv(toUInt32(?3 + (number + 1) * ?1), ?1) * ?1) AS time,
        toUInt32(0) AS addresses,
        toUInt32(0) AS deposits
      FROM numbers(?2)

      UNION ALL

      SELECT
        toDateTime(intDiv(toUInt32(dt), ?1) * ?1) AS time,
        total_addresses AS addresses,
        deposits AS deposits
      FROM (
        SELECT
          toStartOfDay(dt) AS dt,
          anyLast(total_addresses) AS total_addresses
        FROM eth_daily_active_addresses
        PREWHERE
          dt < toDateTime(today()) AND
          dt >= toDateTime(?3) AND
          dt <= toDateTime(?4)
        GROUP BY dt

        UNION ALL

        SELECT
          toStartOfDay(dt) AS dt,
          uniq(address) AS total_addresses
        FROM eth_daily_active_addresses_list
        PREWHERE
          dt >= toDateTime(today()) AND
          dt >= toDateTime(?3) AND
          dt <= toDateTime(?4)
        GROUP BY dt
      )

      ANY LEFT JOIN(
        SELECT
          sum(total_addresses) AS deposits,
          dt
        FROM(
          SELECT DISTINCT
            exchange,
            dt,
            contract,
            total_addresses
          FROM daily_active_deposits
          PREWHERE
            dt <= toDateTime(today()) AND
            dt >= toDateTime(?3) AND
            dt <= toDateTime(?4)
        )
        GROUP BY dt
      ) USING(dt)

    )
    GROUP BY dt
    ORDER BY dt
    """

    args = [interval, span, from_datetime_unix, to_datetime_unix]

    {query, args}
  end
end
