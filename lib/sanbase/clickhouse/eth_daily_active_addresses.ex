defmodule Sanbase.Clickhouse.EthDailyActiveAddresses do
  @moduledoc ~s"""
  Uses ClickHouse to calculate the daily active addresses for ETH
  """

  require Sanbase.ClickhouseRepo, as: ClickhouseRepo
  import Sanbase.Utils.Math, only: [to_integer: 1]

  alias Sanbase.DateTimeUtils

  @type active_addresses :: %{
          datetime: %DateTime{},
          active_addresses: non_neg_integer()
        }

  @doc ~s"""
  Returns the average value of the daily active addresses 
  for Ethereum in a given interval [form, to].
  The last day is included in the AVG multiplied by coefficient (24 / current_hour)
  """

  @spec average_active_addresses(
          %DateTime{},
          %DateTime{}
        ) :: {:ok, non_neg_integer()} | {:error, String.t()}

  def average_active_addresses(from, to) do
    from_datetime_unix = DateTime.to_unix(from)
    to_datetime_unix = DateTime.to_unix(to)
    # multiply last day value by today_coefficient because value is not for full day
    today_coefficient = 24 / (DateTime.to_time(Timex.now()).hour + 1)

    query = """
    SELECT AVG(total_addresses) as active_addresses
    FROM (
      SELECT dt, toFloat64(anyLast(total_addresses)) as total_addresses
      FROM eth_daily_active_addresses
      WHERE
      dt < toDateTime(today()) AND
      dt >= toDateTime(?1) AND
      dt <= toDateTime(?2)
      GROUP BY dt
      
      UNION ALL
      
      SELECT dt, (toFloat64(uniq(address)) * toFloat64(#{today_coefficient})) as total_addresses
      FROM eth_daily_active_addresses_list
      WHERE dt >= toDateTime(today()) AND
      dt >= toDateTime(?1) AND
      dt <= toDateTime(?2)
      GROUP BY dt
    )
    """

    args = [from_datetime_unix, to_datetime_unix]

    {:ok, result} =
      ClickhouseRepo.query_transform(query, args, fn [avg_active_addresses] ->
        avg_active_addresses |> to_integer()
      end)

    {:ok, result |> List.first()}
  end

  @doc ~s"""
  Returns the active addresses for Ethereum chunked in intervals between [from, to]
  If last day is included in the [from, to] the value is the realtime value in the current moment
  """

  @spec average_active_addresses(
          %DateTime{},
          %DateTime{},
          String.t()
        ) :: {:ok, list(active_addresses)} | {:error, String.t()}

  def average_active_addresses(from, to, interval) do
    interval = DateTimeUtils.compound_duration_to_seconds(interval)
    from_datetime_unix = DateTime.to_unix(from)
    to_datetime_unix = DateTime.to_unix(to)
    span = div(to_datetime_unix - from_datetime_unix, interval)

    query = """
    SELECT toUnixTimestamp(time) as dt, SUM(value) as active_addresses
    FROM (
      SELECT
        toDateTime(intDiv(toUInt32(?3 + (number + 1) * ?1), ?1) * ?1) as time,
        toUInt32(0) AS value
      FROM numbers(?2)

      UNION ALL

      SELECT toDateTime(intDiv(toUInt32(dt), ?1) * ?1) as time, total_addresses as value
      FROM (
        SELECT dt, anyLast(total_addresses) as total_addresses
        FROM eth_daily_active_addresses
        WHERE
        dt < toDateTime(today()) AND
        dt >= toDateTime(?3) AND
        dt <= toDateTime(?4)
        GROUP BY dt
        
        UNION ALL
        
        SELECT dt, uniq(address) as total_addresses
        FROM eth_daily_active_addresses_list
        WHERE dt >= toDateTime(today()) AND
        dt >= toDateTime(?3) AND
        dt <= toDateTime(?4)
        GROUP BY dt
      )
    )
    group by dt
    order by dt
    """

    args = [interval, span, from_datetime_unix, to_datetime_unix]

    ClickhouseRepo.query_transform(query, args, fn [dt, active_addresses] ->
      %{
        datetime: DateTime.from_unix!(dt),
        active_addresses: active_addresses |> to_integer()
      }
    end)
  end

  @spec average_active_addresses!(
          %DateTime{},
          %DateTime{},
          String.t()
        ) :: list(active_addresses)

  def average_active_addresses!(from, to, interval) do
    case average_active_addresses(from, to, interval) do
      {:ok, result} -> result
      {:error, error} -> raise(error)
    end
  end
end
