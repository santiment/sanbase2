defmodule Sanbase.Clickhouse.TopHolders do
  @moduledoc ~s"""
  Uses ClickHouse to calculate the supply in exchanges
  """

  import Sanbase.Math, only: [to_integer: 1]

  alias Sanbase.DateTimeUtils
  alias Sanbase.Model.Project

  require Sanbase.ClickhouseRepo, as: ClickhouseRepo

  @type top_holders :: %{
          datetime: DateTime.t(),
          percent_total_supply_in_exchanges: float(),
          percent_total_supply_outside_exchange: float(),
          percent_total_supply_in_holders: float()
        }

  @spec top_holders(
          String.t(),
          non_neg_integer(),
          DateTime.t(),
          DateTime.t()
        ) :: {:ok, list(top_holders)} | {:error, String.t()}
  def top_holders(slug, number_of_holders, from, to) do
    {query, args} = top_holders_query(slug, number_of_holders, from, to)

    ClickhouseRepo.query_transform(
      query,
      args,
      fn [dt, in_exchanges, outside_exchanges, in_holders] ->
        %{
          datetime: DateTime.from_unix!(dt),
          percent_total_supply_in_exchanges: in_exchanges,
          percent_total_supply_outside_exchange: outside_exchanges,
          percent_total_supply_in_holders: in_holders
        }
      end
    )
  end

  defp top_holders_query(slug, number_of_holders, from, to) do
    from_datetime_unix = DateTime.to_unix(from)
    to_datetime_unix = DateTime.to_unix(to)
    {:ok, contract, token_decimals} = Project.contract_info_by_slug(slug)

    query = """
    SELECT
      toUnixTimestamp(intDiv(toUInt32(toDateTime(dt)), 86400) * 86400) AS time,
      sumIf(partOfTotal, isExchange = 1) * 100 AS tse,
      sumIf(partOfTotal, isExchange = 0) * 100 AS tsne,
      sum(partOfTotal) * 100 AS tsth
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

    args = [token_decimals, contract, number_of_holders, from_datetime_unix, to_datetime_unix]

    {query, args}
  end
end
