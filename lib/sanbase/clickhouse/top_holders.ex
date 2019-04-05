defmodule Sanbase.Clickhouse.TopHolders do
  @moduledoc ~s"""
  Uses ClickHouse to calculate the percent supply in exchanges, non exchanges and combined
  """

  alias Sanbase.DateTimeUtils
  alias Sanbase.Model.Project

  require Sanbase.ClickhouseRepo, as: ClickhouseRepo

  @type percent_of_total_supply :: %{
          datetime: DateTime.t(),
          in_exchanges: number(),
          outside_exchanges: number(),
          in_top_holders_total: number()
        }

  @spec percent_of_total_supply(
          String.t(),
          non_neg_integer(),
          DateTime.t(),
          DateTime.t()
        ) :: {:ok, list(percent_of_total_supply)} | {:error, String.t()}
  def percent_of_total_supply(slug, number_of_holders, from, to) do
    {query, args} = percent_of_total_supply_query(slug, number_of_holders, from, to)

    ClickhouseRepo.query_transform(
      query,
      args,
      fn [dt, in_exchanges, outside_exchanges, in_holders] ->
        %{
          datetime: DateTime.from_unix!(dt),
          in_exchanges: in_exchanges,
          outside_exchanges: outside_exchanges,
          in_top_holders_total: in_holders
        }
      end
    )
  end

  defp percent_of_total_supply_query(slug, number_of_holders, from, to) do
    from_datetime_unix = DateTime.to_unix(from)
    to_datetime_unix = DateTime.to_unix(to)
    {:ok, contract, token_decimals} = Project.contract_info_by_slug(slug)
    interval = DateTimeUtils.compound_duration_to_seconds("1d")

    query = """
    SELECT
      toUnixTimestamp(intDiv(toUInt32(toDateTime(dt)), ?6) * ?6) AS time,
      sumIf(partOfTotal, isExchange = 1) * 100 AS in_exchanges,
      sumIf(partOfTotal, isExchange = 0) * 100 AS outside_exchanges,
      in_exchanges + outside_exchanges AS in_top_holders_total
    FROM
    (
      SELECT
        dt,
        contract,
        address,
        rank,
        value,
        partOfTotal
      FROM
      (
        SELECT *
        FROM
        (
          SELECT
            dt,
            contract,
            address,
            rank,
            value,
            partOfTotal
          FROM
          (
            SELECT
              dt,
              contract,
              address,
              rank,
              value / pow(10, ?1) AS value,
              multiIf(valueTotal > 0, value / (valueTotal / pow(10, ?1)), 0) AS partOfTotal
            FROM
            (
              SELECT *
              FROM eth_top_holders
              PREWHERE (contract = ?2) AND
                (rank <= ?3) AND
                ((dt >= toStartOfDay(toDateTime(?4))) AND
                (dt <= toStartOfDay(toDateTime(?5))))
            )
            GLOBAL ANY LEFT JOIN
            (
              SELECT
                dt,
                sum(value) AS valueTotal
              FROM eth_top_holders
              PREWHERE (contract = ?2) AND
               (address IN ('TOTAL', 'freeze')) AND
               ((dt >= toStartOfDay(toDateTime(?4))) AND (dt <= toStartOfDay(toDateTime(?5))))
              GROUP BY dt
            ) USING (dt)
          )
        )
      )
    )
    GLOBAL ANY LEFT JOIN
    (
      SELECT
        address,
        1 AS isExchange
      FROM exchange_addresses
    ) USING (address)
    GROUP BY dt
    ORDER BY dt ASC
    """

    args = [
      token_decimals,
      contract,
      number_of_holders,
      from_datetime_unix,
      to_datetime_unix,
      interval
    ]

    {query, args}
  end
end
