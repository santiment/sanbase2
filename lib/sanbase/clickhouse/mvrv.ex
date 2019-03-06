defmodule Sanbase.Clickhouse.MVRV do
  @moduledoc ~s"""
  Uses ClickHouse to calculate MVRV Ratio(Market-Value-to-Realized-Value)
  """

  require Sanbase.ClickhouseRepo, as: ClickhouseRepo
  alias Sanbase.DateTimeUtils
  alias Sanbase.Model.Project

  @type mvrv_ratio :: %{
          datetime: %DateTime{},
          ratio: float
        }

  @spec mvrv_ratio(
          String.t(),
          DateTime.t(),
          DateTime.t(),
          String.t()
        ) :: {:ok, list(mvrv_ratio)} | {:error, String.t()}
  def mvrv_ratio(slug, from, to, interval) do
    ticker = Project.ticker_by_slug(slug)
    ticker_slug = "#{ticker}_#{slug}"

    from_datetime_unix = DateTime.to_unix(from)
    to_datetime_unix = DateTime.to_unix(to)
    interval = DateTimeUtils.compound_duration_to_seconds(interval)

    query = """
    SELECT
        toUnixTimestamp((intDiv(toUInt32(toDateTime(dt)), ?1) * ?1)) AS time,
        avgIf(value, metric = 'marketcap_usd') / avgIf(value, metric = 'stack_realized_value_usd') AS ratio
    FROM daily_metrics
    PREWHERE
      ticker_slug = ?2 AND
      dt >= toDate(?3) AND
      dt <= toDate(?4) AND
      metric IN ('stack_realized_value_usd', 'marketcap_usd')
    GROUP BY time
    ORDER BY time ASC
    """

    args = [interval, ticker_slug, from_datetime_unix, to_datetime_unix]

    ClickhouseRepo.query_transform(query, args, fn [dt, mvrv_ratio] ->
      %{
        datetime: DateTime.from_unix!(dt),
        ratio: mvrv_ratio
      }
    end)
  end
end
