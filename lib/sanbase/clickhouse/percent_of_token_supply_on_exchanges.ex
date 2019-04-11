defmodule Sanbase.Clickhouse.PercentOfTokenSupplyOnExchanges do
  @moduledoc ~s"""
  Uses ClickHouse to calculate what percent of token supply is on exchanges
  """

  alias Sanbase.DateTimeUtils
  alias Sanbase.Model.Project
  require Sanbase.ClickhouseRepo, as: ClickhouseRepo

  @type percent_on_exchanges :: %{
          datetime: DateTime.t(),
          percent_on_exchanges: number()
        }

  @spec percent_on_exchanges(
          String.t(),
          DateTime.t(),
          DateTime.t(),
          String.t()
        ) :: {:ok, list(percent_on_exchanges)} | {:error, String.t()}
  def percent_on_exchanges(slug, from, to, interval) do
    {query, args} = percent_on_exchanges_query(slug, from, to, interval)

    ClickhouseRepo.query_transform(
      query,
      args,
      fn [dt, tokens_on_exchanges_ratio] ->
        %{
          datetime: DateTime.from_unix!(dt),
          percent_on_exchanges: tokens_on_exchanges_ratio * 100
        }
      end
    )
  end

  defp percent_on_exchanges_query(slug, from, to, interval) do
    ticker = Project.ticker_by_slug(slug)
    ticker_slug = "#{ticker}_#{slug}"

    from_datetime_unix = DateTime.to_unix(from)
    to_datetime_unix = DateTime.to_unix(to)
    interval = DateTimeUtils.compound_duration_to_seconds(interval)

    query = """
    SELECT
      time,
      1 - non_exchange_token_supply / total_supply AS tokens_on_exchanges_ratio
    FROM (
      SELECT
        toUnixTimestamp((intDiv(toUInt32(toDateTime(dt)), ?1) * ?1)) AS time,
        avg(value / pow(10, token_decimals)) AS total_supply
      FROM erc20_balances
      GLOBAL ANY INNER JOIN (
        SELECT
          contract_address AS contract,
          token_decimals
        FROM contract_ticker_slug_map
        WHERE ticker_slug = ?2
      ) USING contract
      PREWHERE
        dt >= toDateTime(?3) AND
        dt <= toDateTime(?4) AND
        address = 'TOTAL' AND
        sign = 1 AND
        contract = (
          SELECT contract_address
          FROM contract_ticker_slug_map
          WHERE ticker_slug = ?2
          LIMIT 1)
      GROUP BY time
    )
    GLOBAL ANY INNER JOIN (
      SELECT
        toUnixTimestamp((intDiv(toUInt32(toDateTime(dt)), ?1) * ?1)) AS time,
        argMax(value, computed_at) AS non_exchange_token_supply
      FROM daily_metrics
      PREWHERE
        ticker_slug = ?2 AND
        dt >= toDate(?3) AND
        dt <= toDate(?4) AND
        metric = 'non_exchange_token_supply'
      GROUP BY time
    ) USING time
    WHERE total_supply >= non_exchange_token_supply
    ORDER BY time
    """

    args = [interval, ticker_slug, from_datetime_unix, to_datetime_unix]

    {query, args}
  end
end
