defmodule Sanbase.Clickhouse.DailyActiveAddresses do
  @moduledoc ~s"""
  Uses ClickHouse to calculate the daily active addresses for an ERC20 token or Ethereum
  """

  alias Sanbase.DateTimeUtils

  require Sanbase.ClickhouseRepo, as: ClickhouseRepo

  def average_active_addresses(contracts, from, to) do
    contracts = List.wrap(contracts)
    from_datetime_unix = DateTime.to_unix(from)
    to_datetime_unix = DateTime.to_unix(to)
    weight = 24 / (DateTime.to_time(Timex.now()).hour + 1)

    args = [from_datetime_unix, to_datetime_unix, contracts |> Enum.reject(&(&1 == "ETH"))]

    query = """
    SELECT contract, AVG(total_addresses) as active_addresses
    FROM (
      SELECT contract, dt, AVG(total_addresses) as total_addresses
      FROM erc20_daily_active_addresses
      WHERE
      contract IN (?3) AND
      dt < toDateTime(today()) AND
      dt >= toDateTime(?1) AND
      dt <= toDateTime(?2)
      GROUP BY contract, dt

      UNION ALL

      SELECT contract, dt, (toFloat64(uniq(address)) * toFloat64(#{weight})) as total_addresses
      FROM erc20_daily_active_addresses_list
      WHERE contract IN (?3) and dt >= toDateTime(today())
      GROUP BY contract, dt
    )
    WHERE
    dt >= toDateTime(?1) AND
    dt <= toDateTime(?2)
    GROUP BY contract
    ORDER BY contract
    """

    {:ok, result} =
      ClickhouseRepo.query_transform(query, args, fn [contract, avg_active_addresses] ->
        {contract, avg_active_addresses |> Float.round() |> trunc()}
      end)

    case Enum.find(contracts, &(&1 == "ETH")) do
      "ETH" ->
        {:ok, eth_result} =
          calc_eth_average_active_addresses(from_datetime_unix, to_datetime_unix)

        Enum.concat(result, eth_result)

      nil ->
        {:ok, result}
    end
  end

  def average_active_addresses("ETH", from, to, interval) do
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

      SELECT toDateTime(intDiv(toUInt32(dt), ?1) * ?1) as time, SUM(total_addresses) as value
      FROM (
        SELECT dt, total_addresses
        FROM eth_daily_active_addresses
        WHERE
        dt < toDateTime(today()) AND
        dt >= toDateTime(?3) AND
        dt <= toDateTime(?4)
        
        UNION ALL
        
        SELECT dt, uniq(address) as total_addresses
        FROM eth_daily_active_addresses_list
        WHERE dt >= toDateTime(today())
        GROUP BY dt
      )
      WHERE
      dt >= toDateTime(?3) AND
      dt <= toDateTime(?4)
      GROUP BY time
    )
    group by dt
    order by dt
    """

    args = [interval, span, from_datetime_unix, to_datetime_unix]

    ClickhouseRepo.query_transform(query, args, fn [dt, active_addresses] ->
      %{
        datetime: DateTime.from_unix!(dt),
        active_addresses: active_addresses |> String.to_integer()
      }
    end)
  end

  def average_active_addresses(contract, from, to, interval) do
    interval = DateTimeUtils.compound_duration_to_seconds(interval)
    from_datetime_unix = DateTime.to_unix(from)
    to_datetime_unix = DateTime.to_unix(to)
    span = div(to_datetime_unix - from_datetime_unix, interval)

    query = """
    SELECT toUnixTimestamp(time) as dt, SUM(value) as active_addresses
    FROM (
      SELECT
        toDateTime(intDiv(toUInt32(?4 + (number + 1) * ?1), ?1) * ?1) as time,
        toUInt32(0) AS value
      FROM numbers(?2)

      UNION ALL

      SELECT toDateTime(intDiv(toUInt32(dt), ?1) * ?1) as time, SUM(total_addresses) as value
      FROM (
        SELECT dt, total_addresses
        FROM erc20_daily_active_addresses
        WHERE contract = ?3 AND
        dt < toDateTime(today()) AND
        dt >= toDateTime(?4) AND
        dt <= toDateTime(?5)
        
        UNION ALL
        
        SELECT dt, uniq(address) as total_addresses
        FROM erc20_daily_active_addresses_list
        WHERE contract = ?3 AND dt >= toDateTime(today())
        GROUP BY dt
      )
      WHERE
      dt >= toDateTime(?4) AND
      dt <= toDateTime(?5)
      GROUP BY time
    )
    group by dt
    order by dt
    """

    args = [interval, span, contract, from_datetime_unix, to_datetime_unix]

    ClickhouseRepo.query_transform(query, args, fn [dt, active_addresses] ->
      %{
        datetime: DateTime.from_unix!(dt),
        active_addresses: active_addresses |> String.to_integer()
      }
    end)
  end

  def calc_eth_average_active_addresses(from, to) do
    # multiply last day value by weight because value is not for full day
    weight = 24 / (DateTime.to_time(Timex.now()).hour + 1)

    query = """
    SELECT AVG(total_addresses) as active_addresses
    FROM (
      SELECT dt, toFloat64(total_addresses) as total_addresses
      FROM eth_daily_active_addresses
      WHERE
      dt < toDateTime(today()) AND
      dt >= toDateTime(?1) AND
      dt <= toDateTime(?2)
      
      UNION ALL
      
      SELECT dt, (toFloat64(uniq(address)) * toFloat64(#{weight})) as total_addresses
      FROM eth_daily_active_addresses_list
      WHERE dt >= toDateTime(today())
      GROUP BY dt
    )
    WHERE
    dt >= toDateTime(?1) AND
    dt <= toDateTime(?2)
    """

    args = [from, to]

    {:ok, result} =
      ClickhouseRepo.query_transform(query, args, fn [avg_active_addresses] ->
        {"ETH", avg_active_addresses}
      end)

    {:ok, result}
  end
end
