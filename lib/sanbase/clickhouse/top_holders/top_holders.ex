defmodule Sanbase.Clickhouse.TopHolders do
  @moduledoc ~s"""
  Uses ClickHouse to calculate the percent supply in exchanges, non exchanges and combined
  """

  alias Sanbase.DateTimeUtils

  alias Sanbase.ClickhouseRepo
  alias Sanbase.Clickhouse.Label

  @type percent_of_total_supply :: %{
          datetime: DateTime.t(),
          in_exchanges: number(),
          outside_exchanges: number(),
          in_top_holders_total: number()
        }

  def top_holders(slug, contract, token_decimals, from, to, number_of_holders) do
    {query, args} =
      top_holders_query(
        slug,
        contract,
        token_decimals,
        from,
        to,
        number_of_holders
      )

    transform_func = fn [dt, address, value, value_usd, part_of_total] ->
      %{
        datetime: DateTime.from_unix!(dt),
        address: address,
        value: value,
        value_usd: value_usd,
        part_of_total: part_of_total
      }
    end

    with {:ok, top_holders} <- ClickhouseRepo.query_transform(query, args, transform_func),
         addresses <- Enum.map(top_holders, & &1.address),
         {:ok, address_labels_map} <- Label.get_address_labels("santiment", addresses) do
      labelled_top_holders =
        top_holders
        |> Enum.map(fn top_holder ->
          labels = Map.get(address_labels_map, top_holder.address, [])
          Map.put(top_holder, :labels, labels)
        end)

      {:ok, labelled_top_holders}
    end
  end

  @spec percent_of_total_supply(
          contract :: String.t(),
          decimals :: non_neg_integer(),
          number_of_top_holders :: non_neg_integer(),
          from :: DateTime.t(),
          to :: DateTime.t(),
          interval :: String.t()
        ) :: {:ok, list(percent_of_total_supply)} | {:error, String.t()}
  def percent_of_total_supply(contract, token_decimals, number_of_holders, from, to, interval) do
    {query, args} =
      percent_of_total_supply_query(
        contract,
        token_decimals,
        number_of_holders,
        from,
        to,
        interval
      )

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

  # helpers

  defp top_holders_query(
         slug,
         contract,
         token_decimals,
         from,
         to,
         number_of_holders
       ) do
    from_datetime_unix = DateTime.to_unix(from)
    to_datetime_unix = DateTime.to_unix(to)

    query = """
    SELECT
      toUnixTimestamp(dt),
      address,
      val as value,
      val * price as value_usd,
      partOfTotal
    FROM(
      SELECT
        max(dt) as dt,
        address,
        anyLast(value) as val,
        any(partOfTotal) as partOfTotal
      FROM(
        SELECT
          dt,
          contract,
          address,
          rank,
          value / pow(10, ?3) AS value,
          multiIf(valueTotal > 0,
          value / (valueTotal / pow(10, ?3)),
          0) AS partOfTotal
        FROM(
          SELECT *
          FROM
            eth_top_holders PREWHERE (contract = ?2)
            AND (address NOT IN ('TOTAL',
            'freeze'))
            AND ((dt >= toStartOfDay(toDateTime(?4)))
            AND (dt <= toStartOfDay(toDateTime(?5)))) ) GLOBAL ANY
        LEFT JOIN (
          SELECT
            dt,
            sum(value) AS valueTotal
          FROM
            eth_top_holders PREWHERE (contract = ?2)
            AND (address IN ('TOTAL','freeze'))
            AND dt >= toStartOfDay(toDateTime(?4))
            AND dt <= toStartOfDay(toDateTime(?5))
          GROUP BY dt
        ) USING (dt) )
      GROUP BY address
      ORDER BY val DESC
      LIMIT ?6
    )
    ALL LEFT JOIN (
      SELECT
        toStartOfDay(dt) as dt,
        avg(value) AS price
      FROM
        intraday_metrics FINAL
        PREWHERE asset_id = (SELECT asset_id FROM asset_metadata FINAL PREWHERE name = ?1 LIMIT 1)
        AND metric_id = (SELECT metric_id FROM metric_metadata FINAL PREWHERE name = 'price_usd' LIMIT 1)
      GROUP BY dt
    ) USING (dt)
    """

    args = [
      slug,
      contract,
      token_decimals,
      from_datetime_unix,
      to_datetime_unix,
      number_of_holders
    ]

    {query, args}
  end

  defp percent_of_total_supply_query(
         contract,
         token_decimals,
         number_of_holders,
         from,
         to,
         interval
       ) do
    from_datetime_unix = DateTime.to_unix(from)
    to_datetime_unix = DateTime.to_unix(to)
    interval_sec = DateTimeUtils.str_to_sec(interval)

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
      interval_sec
    ]

    {query, args}
  end
end
