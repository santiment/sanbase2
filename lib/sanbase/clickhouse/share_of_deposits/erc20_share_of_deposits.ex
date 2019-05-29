defmodule Sanbase.Clickhouse.Erc20ShareOfDeposits do
  @moduledoc ~s"""
  Uses ClickHouse to calculate share of deposits from daily active addresses for an ERC20 token
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

  def first_datetime(contract) do
    contract = String.downcase(contract)

    query = """
    SELECT min(dt) FROM daily_active_deposits WHERE contract = ?1
    """

    args = [contract]

    ClickhouseRepo.query_transform(query, args, fn [datetime] ->
      datetime |> Sanbase.DateTimeUtils.from_erl!()
    end)
    |> case do
      {:ok, [first_datetime]} -> {:ok, first_datetime}
      error -> error
    end
  end

  @doc ~s"""
  Returns the share of deposits from daily active addresses for contract chunked in intervals between [from, to]
  If last day is included in the [from, to] the value is the realtime value in the current moment
  """
  @spec share_of_deposits(
          String.t(),
          %DateTime{},
          %DateTime{},
          String.t()
        ) :: {:ok, list(share_of_deposits)} | {:error, String.t()}
  def share_of_deposits(contract, from, to, interval) do
    {query, args} = share_of_deposits_query(contract, from, to, interval)

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

  defp share_of_deposits_query(contract, from, to, interval) do
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
        toDateTime(intDiv(toUInt32(?4 + (number + 1) * ?1), ?1) * ?1) AS time,
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
        FROM erc20_daily_active_addresses
        PREWHERE
          contract = ?3 AND
          dt < toDateTime(today()) AND
          dt >= toDateTime(?4) AND
          dt <= toDateTime(?5)
        GROUP BY contract, dt

        UNION ALL

        SELECT
          toStartOfDay(dt) AS dt,
          uniq(address) AS total_addresses
        FROM erc20_daily_active_addresses_list
        PREWHERE
          contract = ?3 AND
          dt >= toDateTime(today()) AND
          dt >= toDateTime(?4) AND
          dt <= toDateTime(?5)
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
            contract = ?3 AND
            dt <= toDateTime(today()) AND
            dt >= toDateTime(?4) AND
            dt <= toDateTime(?5)
        )
        GROUP BY dt
      ) USING(dt)

    )
    GROUP BY dt
    ORDER BY dt
    """

    args = [interval, span, contract, from_datetime_unix, to_datetime_unix]

    {query, args}
  end
end
