defmodule Sanbase.Clickhouse.EthDailyActiveAddresses do
  @moduledoc ~s"""
  Uses ClickHouse to calculate the daily active addresses for ETH
  """

  require Sanbase.ClickhouseRepo, as: ClickhouseRepo
  import Sanbase.Math, only: [to_integer: 1]

  alias Sanbase.DateTimeUtils

  @type active_addresses :: %{
          datetime: %DateTime{},
          active_addresses: non_neg_integer(),
          active_deposits: non_neg_integer(),
          share_of_deposits: number()
        }

  @type active_addresses_with_deposits :: %{
          datetime: %DateTime{},
          active_addresses: non_neg_integer(),
          active_deposits: non_neg_integer(),
          share_of_deposits: number()
        }

  @doc ~s"""
  Gets the current value for active addresses for today.
  Returns an tuple {:ok, float}
  """
  @spec realtime_active_addresses() :: {:ok, float()}
  def realtime_active_addresses() do
    query = """
    SELECT coalesce(uniq(address), 0) as active_addresses
    FROM eth_daily_active_addresses_list
    PREWHERE dt >= toDateTime(today())
    """

    {:ok, result} =
      ClickhouseRepo.query_transform(query, [], fn [active_addresses] ->
        active_addresses |> to_integer
      end)

    {:ok, result |> List.first()}
  end

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
      ClickhouseRepo.query_transform(query, args, fn
        [nil] -> 0
        [avg_active_addresses] -> avg_active_addresses |> to_integer()
      end)

    {:ok, result |> List.first()}
  end

  @doc ~s"""
  Returns the active addresses and deposits share for Ethereum chunked in intervals between [from, to]
  If last day is included in the [from, to] the value is the realtime value in the current moment
  """
  @spec average_active_addresses_with_deposits(
          %DateTime{},
          %DateTime{},
          String.t()
        ) :: {:ok, list(active_addresses_with_deposits)} | {:error, String.t()}
  def average_active_addresses_with_deposits(from, to, interval) do
    {query, args} = average_active_addresses_with_deposits_query(from, to, interval)

    ClickhouseRepo.query_transform(query, args, fn [
                                                     dt,
                                                     active_addresses,
                                                     active_deposits,
                                                     share_of_deposits
                                                   ] ->
      %{
        datetime: DateTime.from_unix!(dt),
        active_addresses: active_addresses |> to_integer(),
        active_deposits: active_deposits |> to_integer(),
        share_of_deposits: share_of_deposits
      }
    end)
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
    {query, args} = average_active_addresses_query(from, to, interval)

    ClickhouseRepo.query_transform(query, args, fn [dt, active_addresses] ->
      %{
        datetime: DateTime.from_unix!(dt),
        active_addresses: active_addresses |> to_integer()
      }
    end)
  end

  defp average_active_addresses_with_deposits_query(from, to, interval) do
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
        toDateTime(intDiv(toUInt32(?3 + (number + 1) * ?1), ?1) * ?1) AS time,
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
        FROM eth_daily_active_addresses
        PREWHERE
          dt < toDateTime(today()) AND
          dt >= toDateTime(?3) AND
          dt <= toDateTime(?4)
        GROUP BY dt

        UNION ALL

        SELECT
          toStartOfDay(dt) AS dt,
          uniq(address) AS total_addresses
        FROM eth_daily_active_addresses_list
        PREWHERE
          dt >= toDateTime(today()) AND
          dt >= toDateTime(?3) AND
          dt <= toDateTime(?4)
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
            dt < toDateTime(today()) AND
            dt >= toDateTime(?3) AND
            dt <= toDateTime(?4)
        )
        GROUP BY dt
      ) USING(dt)

    )
    GROUP BY dt
    ORDER BY dt
    """

    args = [interval, span, from_datetime_unix, to_datetime_unix]

    {query, args}
  end

  def average_active_addresses_query(from, to, interval) do
    interval = DateTimeUtils.compound_duration_to_seconds(interval)
    from_datetime_unix = DateTime.to_unix(from)
    to_datetime_unix = DateTime.to_unix(to)
    span = div(to_datetime_unix - from_datetime_unix, interval) |> max(1)

    query = """
    SELECT
      toUnixTimestamp(time) AS dt,
      SUM(value) AS active_addresses
    FROM (
      SELECT
        toDateTime(intDiv(toUInt32(?3 + (number + 1) * ?1), ?1) * ?1) AS time,
        toUInt32(0) AS value
      FROM numbers(?2)
      UNION ALL
      SELECT
        toDateTime(intDiv(toUInt32(dt), ?1) * ?1) AS time,
        total_addresses AS value
      FROM (
        SELECT
          toStartOfDay(dt) AS dt,
          anyLast(total_addresses) AS total_addresses
        FROM eth_daily_active_addresses
        WHERE
          dt < toDateTime(today()) AND
          dt >= toDateTime(?3) AND
          dt <= toDateTime(?4)
        GROUP BY dt
        UNION ALL
        SELECT
          toStartOfDay(dt) AS dt,
          uniq(address) AS total_addresses
        FROM eth_daily_active_addresses_list
        WHERE
          dt >= toDateTime(today()) AND
          dt >= toDateTime(?3) AND
          dt <= toDateTime(?4)
        GROUP BY dt
      )
    )
    GROUP BY dt
    ORDER BY dt
    """

    args = [interval, span, from_datetime_unix, to_datetime_unix]

    {query, args}
  end

  def average_active_addresses!(from, to, interval) do
    case average_active_addresses(from, to, interval) do
      {:ok, result} -> result
      {:error, error} -> raise(error)
    end
  end
end
