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
    {query, args} = mvrv_query(slug, from, to, interval)

    ClickhouseRepo.query_transform(query, args, fn [dt, mvrv_ratio] ->
      %{
        datetime: DateTime.from_unix!(dt),
        ratio: mvrv_ratio
      }
    end)
    |> fill_last_seen()
  end

  defp mvrv_query(slug, from, to, interval) do
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

    {query, args}
  end

  defp fill_last_seen({:ok, [%{ratio: ratio} | _] = result}) do
    result
    |> Enum.reduce({ratio, []}, &fill_element/2)
    |> elem(1)
    |> Enum.reverse()

    IO.inspect(result)

    {:ok, result}
  end

  defp fill_last_seen(data), do: data

  defp fill_element(%{ratio: nil, datetime: dt}, {last_seen, acc}),
    do: {last_seen, [%{ratio: last_seen, datetime: dt} | acc]}

  defp fill_element(%{ratio: ratio, datetime: dt}, {_last_seen, acc}),
    do: {ratio, [%{ratio: ratio, datetime: dt} | acc]}
end
