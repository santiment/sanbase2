defmodule Sanbase.Clickhouse.EthDailyActiveAddresses do
  @moduledoc ~s"""
  Uses ClickHouse to calculate the daily active addresses for ETH

  Note: Experimental. Define the schema but do not use it now.
  """

  use Ecto.Schema

  @table "eth_daily_active_addresses"

  @timestamps_opts updated_at: false
  @primary_key false
  schema "eth_daily_active_addresses" do
    field(:dt, :utc_datetime, primary_key: true)
    field(:total_transactions, :integer)
  end

  def changeset(_, _attrs \\ %{}) do
    raise "Should not try to change eth daily active addresses"
  end

  def active_addresses(from, to) do
    from_datetime_unix = DateTime.to_unix(from)
    to_datetime_unix = DateTime.to_unix(to)

    query = """
    SELECT sum(total_addresses) as active_addresses
    FROM #{@table}
    PREWHERE dt >= toDateTime(?1) and
    dt <= toDateTime(?2)
    group by dt
    order by dt
    """

    args = [from_datetime_unix, to_datetime_unix]

    ClickhouseRepo.query_transform(query, args, fn [active_addresses] ->
      [active_addresses |> String.to_integer()]
    end)
    |> case do
      {:ok, []} -> {:ok, 0}
      {:ok, active_addresses} -> {:ok, active_addresses |> List.first()}
    end
  end

  def active_addresses(from, to, interval) do
    interval = DateTimeUtils.compound_duration_to_seconds(interval)
    from_datetime_unix = DateTime.to_unix(from)
    to_datetime_unix = DateTime.to_unix(to)
    span = div(to_datetime_unix - from_datetime_unix, interval)

    query = """
    SELECT toUnixTimestamp(time) as dt, SUM(value) as active_addresses
    FROM (
      SELECT
        toDateTime(intDiv(toUInt32(?4 + number * ?1), ?1) * ?1) as time,
        toUInt32(0) AS value
      FROM numbers(?2)

      UNION ALL

      SELECT toDateTime(intDiv(toUInt32(dt), ?1) * ?1) as time, sum(total_addresses) as value
      FROM #{@table}
      PREWHERE dt >= toDateTime(?3) and
      dt <= toDateTime(?4)
      group by time
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

  def realtime_active_addresses() do
    query = """
    SELECT toUnixTimestamp(dt), uniq(address) as total_addresses
    FROM eth_daily_active_addresses_list
    WHERE dt >= toDateTime(today())
    GROUP BY dt
    """

    ClickhouseRepo.query_transform(query, [], fn [dt, active_addresses] ->
      %{
        datetime: DateTime.from_unix!(dt),
        active_addresses: active_addresses |> String.to_integer()
      }
    end)
  end
end
