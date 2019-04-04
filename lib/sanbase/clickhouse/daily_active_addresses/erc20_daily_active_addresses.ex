defmodule Sanbase.Clickhouse.Erc20DailyActiveAddresses do
  @moduledoc ~s"""
  Uses ClickHouse to calculate the daily active addresses for an ERC20 token
  """

  require Sanbase.ClickhouseRepo, as: ClickhouseRepo
  import Sanbase.Math, only: [to_integer: 1]

  alias Sanbase.DateTimeUtils

  @type contracts :: String.t() | list(String.t())

  @type contract_daa_tuple :: {
          String.t(),
          non_neg_integer()
        }

  @type active_addresses :: %{
          datetime: %DateTime{},
          active_addresses: non_neg_integer(),
          active_deposits: non_neg_integer(),
          share_of_deposits: number()
        }

  @doc ~s"""
  Returns the average value of the daily active addresses
  for every contract in a given interval [form, to].
  The last day is included in the AVG multiplied by coefficient (24 / current_hour)
  Returns a list of tuples {contract, active_addresses}
  """
  @spec average_active_addresses(
          contracts,
          %DateTime{},
          %DateTime{}
        ) :: {:ok, list(contract_daa_tuple)} | {:error, String.t()}
  def average_active_addresses(contracts, from, to) do
    contracts = List.wrap(contracts)
    from_datetime_unix = DateTime.to_unix(from)
    to_datetime_unix = DateTime.to_unix(to)
    # multiply last day value by today_coefficient because value is not for full day
    today_coefficient = 24 / (DateTime.to_time(Timex.now()).hour + 1)

    args = [from_datetime_unix, to_datetime_unix, contracts]

    query = """
    SELECT contract, AVG(total_addresses) as active_addresses
    FROM (
      SELECT contract, toStartOfDay(dt) as dt, toFloat64(anyLast(total_addresses)) as total_addresses
      FROM erc20_daily_active_addresses
      PREWHERE
      contract IN (?3) AND
      dt < toDateTime(today()) AND
      dt >= toDateTime(?1) AND
      dt <= toDateTime(?2)
      GROUP BY contract, dt

      UNION ALL

      SELECT contract, toStartOfDay(dt) as dt, (toFloat64(uniq(address)) * toFloat64(#{
      today_coefficient
    })) as total_addresses
      FROM erc20_daily_active_addresses_list
      PREWHERE contract IN (?3) and dt >= toDateTime(today()) AND
      dt >= toDateTime(?1) AND
      dt <= toDateTime(?2)
      GROUP BY contract, dt
    )
    GROUP BY contract
    """

    ClickhouseRepo.query_transform(query, args, fn [contract, avg_active_addresses] ->
      {contract, avg_active_addresses |> to_integer()}
    end)
  end

  @doc ~s"""
  Gets the current value for active addresses for today.
  Returns a list of tuples {contract, active_addresses}
  """
  @spec realtime_active_addresses(contracts) ::
          {:ok, list(contract_daa_tuple)} | {:error, String.t()}
  def realtime_active_addresses(contracts) do
    contracts = List.wrap(contracts)

    args = [contracts]

    query = """
    SELECT contract, coalesce(uniq(address), 0) as active_addresses
    FROM erc20_daily_active_addresses_list
    PREWHERE contract IN (?1) and dt >= toDateTime(today())
    GROUP BY contract, dt
    """

    ClickhouseRepo.query_transform(query, args, fn
      [contract, active_addresses] ->
        {contract, active_addresses |> to_integer()}
    end)
  end

  @doc ~s"""
  Returns the active addresses for a contract chunked in intervals between [from, to]
  If last day is included in the [from, to] the value is the realtime value in the current moment
  """
  @spec average_active_addresses(
          String.t(),
          %DateTime{},
          %DateTime{},
          String.t()
        ) :: {:ok, list(active_addresses)} | {:error, String.t()}
  def average_active_addresses(contract, from, to, interval) do
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
        toDateTime(intDiv(toUInt32(?4 + (number + 1) * ?1), ?1) * ?1) AS time,
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
        FROM erc20_daily_active_addresses
        PREWHERE
          contract = ?3 AND
          dt < toDateTime(today()) AND
          dt >= toDateTime(?4) AND
          dt <= toDateTime(?5)
        GROUP BY contract, dt

        UNION ALL

        SELECT
          toStartOfDay(dt) AS dt,
          uniq(address) AS total_addresses
        FROM erc20_daily_active_addresses_list
        PREWHERE
          contract = ?3 AND
          dt >= toDateTime(today()) AND
          dt >= toDateTime(?4) AND
          dt <= toDateTime(?5)
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
            contract = ?3 AND
            dt < toDateTime(today()) AND
            dt >= toDateTime(?4) AND
            dt <= toDateTime(?5)
        )
        GROUP BY dt
      ) USING(dt)

    )
    GROUP BY dt
    ORDER BY dt
    """

    args = [interval, span, contract, from_datetime_unix, to_datetime_unix]

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

  @spec average_active_addresses!(
          String.t(),
          %DateTime{},
          %DateTime{},
          String.t()
        ) :: list(active_addresses)
  def average_active_addresses!(contract, from, to, interval) do
    case average_active_addresses(contract, from, to, interval) do
      {:ok, result} -> result
      {:error, error} -> raise(error)
    end
  end
end
