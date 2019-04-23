defmodule Sanbase.Clickhouse.RealizedValue do
  @moduledoc ~s"""
  Uses ClickHouse to calculate Realized Value
  """

  require Sanbase.ClickhouseRepo, as: ClickhouseRepo
  alias Sanbase.DateTimeUtils
  alias Sanbase.Model.Project

  @type realized_value :: %{
          datetime: DateTime.t(),
          realized_value: integer,
          non_exchange_realized_value: integer
        }

  @spec realized_value(
          String.t(),
          DateTime.t(),
          DateTime.t(),
          String.t()
        ) :: {:ok, list(realized_value)} | {:error, String.t()}
  def realized_value(slug, from, to, interval) do
    {query, args} = realized_value_query(slug, from, to, interval)

    ClickhouseRepo.query_transform(
      query,
      args,
      fn [dt, realized_value, non_exchange_realized_value] ->
        %{
          datetime: DateTime.from_unix!(dt),
          realized_value: realized_value,
          non_exchange_realized_value: non_exchange_realized_value
        }
      end
    )
    |> fill_last_seen()
  end

  defp realized_value_query(slug, from, to, interval) do
    ticker = Project.ticker_by_slug(slug)
    ticker_slug = "#{ticker}_#{slug}"

    from_datetime_unix = DateTime.to_unix(from)
    to_datetime_unix = DateTime.to_unix(to)
    interval = DateTimeUtils.compound_duration_to_seconds(interval)

    query = """
    SELECT
        toUnixTimestamp((intDiv(toUInt32(toDateTime(dt)), ?1) * ?1)) AS time,
        avgIf(value, metric = 'stack_realized_value_usd') AS realized_value,
        avgIf(value, metric = 'non_exchange_realized_value_usd') AS non_exchange_realized_value
    FROM daily_metrics
    PREWHERE
      ticker_slug = ?2 AND
      dt >= toDate(?3) AND
      dt <= toDate(?4) AND
      metric in ('stack_realized_value_usd', 'non_exchange_realized_value_usd')
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
              realized_value: realized_value,
              non_exchange_realized_value: non_exchange_realized_value
            }
            | _
          ] = result}
       ) do
    filled_result =
      result
      |> Enum.reduce({realized_value, non_exchange_realized_value, []}, &fill_element/2)
      |> elem(2)
      |> Enum.reverse()

    {:ok, filled_result}
  end

  defp fill_last_seen(data), do: data

  defp fill_element(
         %{realized_value: nil, non_exchange_realized_value: nil, datetime: dt},
         {last_seen_realized_value, last_seen_non_exchange_realized_value, acc}
       ) do
    {last_seen_realized_value, last_seen_non_exchange_realized_value,
     [
       %{
         realized_value: last_seen_realized_value,
         non_exchange_realized_value: last_seen_non_exchange_realized_value,
         datetime: dt
       }
       | acc
     ]}
  end

  defp fill_element(
         %{
           realized_value: realized_value,
           non_exchange_realized_value: non_exchange_realized_value,
           datetime: dt
         },
         {_last_seen_realized_value, _last_seen_non_exchange_realized_value, acc}
       ) do
    {realized_value, non_exchange_realized_value,
     [
       %{
         realized_value: realized_value,
         non_exchange_realized_value: non_exchange_realized_value,
         datetime: dt
       }
       | acc
     ]}
  end
end
