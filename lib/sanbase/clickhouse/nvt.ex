defmodule Sanbase.Clickhouse.NVT do
  @moduledoc ~s"""
  Uses ClickHouse to calculate NVT (Network-Value-to-Transactions-Ratio)
  """

  alias Sanbase.DateTimeUtils
  alias Sanbase.Model.Project
  require Sanbase.ClickhouseRepo, as: ClickhouseRepo

  @type nvt_ratio :: %{
          datetime: DateTime.t(),
          nvt_ratio_circulation: number(),
          nvt_ratio_tx_volume: number()
        }

  @spec nvt_ratio(
          String.t(),
          DateTime.t(),
          DateTime.t(),
          String.t()
        ) :: {:ok, list(nvt_ratio)} | {:error, String.t()}
  def nvt_ratio(slug, from, to, interval) do
    {query, args} = nvt_ratio_query(slug, from, to, interval)

    ClickhouseRepo.query_transform(
      query,
      args,
      fn [dt, _price_usd, nvt_ratio_circulation, nvt_ratio_tx_volume] ->
        %{
          datetime: DateTime.from_unix!(dt),
          nvt_ratio_circulation: nvt_ratio_circulation,
          nvt_ratio_tx_volume: nvt_ratio_tx_volume
        }
      end
    )
    |> fill_last_seen()
  end

  defp nvt_ratio_query(slug, from, to, interval) do
    ticker = Project.ticker_by_slug(slug)
    ticker_slug = "#{ticker}_#{slug}"

    from_datetime_unix = DateTime.to_unix(from)
    to_datetime_unix = DateTime.to_unix(to)
    interval = DateTimeUtils.compound_duration_to_seconds(interval)

    query = """
    SELECT
        toUnixTimestamp((intDiv(toUInt32(toDateTime(dt)), ?1) * ?1)) AS time,
        avgIf(value, metric = 'price_usd') as price_usd,
        avgIf(value, metric = 'marketcap_usd')/(avgIf(value, metric = 'circulation_1d') * price_usd) AS nvt_ratio_circulation,
        avgIf(value, metric = 'marketcap_usd')/(avgIf(value, metric = 'transaction_volume') * price_usd) AS nvt_ratio_tx_volume

    FROM daily_metrics
    PREWHERE
      ticker_slug = ?2 AND
      dt >= toDate(?3) AND
      dt <= toDate(?4) AND
      metric in ('price_usd', 'marketcap_usd', 'transaction_volume', 'circulation_1d')
    GROUP BY time
    ORDER BY time ASC
    """

    args = [interval, ticker_slug, from_datetime_unix, to_datetime_unix]

    {query, args}
  end

  defp fill_last_seen(
         {:ok,
          [
            %{
              nvt_ratio_circulation: nvt_ratio_circulation,
              nvt_ratio_tx_volume: nvt_ratio_tx_volume
            }
            | _
          ] = result}
       ) do
    filled_result =
      result
      |> Enum.reduce({nvt_ratio_circulation, nvt_ratio_tx_volume, []}, &fill_element/2)
      |> elem(2)
      |> Enum.reverse()

    {:ok, filled_result}
  end

  defp fill_last_seen(data), do: data

  defp fill_element(
         %{nvt_ratio_circulation: nil, nvt_ratio_tx_volume: nil, datetime: dt},
         {last_seen_nvt_ratio_circulation, last_seen_nvt_ratio_tx_volume, acc}
       ) do
    {last_seen_nvt_ratio_circulation, last_seen_nvt_ratio_tx_volume,
     [
       %{
         nvt_ratio_circulation: last_seen_nvt_ratio_circulation,
         nvt_ratio_tx_volume: last_seen_nvt_ratio_tx_volume,
         datetime: dt
       }
       | acc
     ]}
  end

  defp fill_element(
         %{
           nvt_ratio_circulation: nvt_ratio_circulation,
           nvt_ratio_tx_volume: nvt_ratio_tx_volume,
           datetime: dt
         },
         {_last_seen_nvt_ratio_circulation, _last_seen_nvt_tx_volume, acc}
       ) do
    {nvt_ratio_circulation, nvt_ratio_tx_volume,
     [
       %{
         nvt_ratio_circulation: nvt_ratio_circulation,
         nvt_ratio_tx_volume: nvt_ratio_tx_volume,
         datetime: dt
       }
       | acc
     ]}
  end
end
