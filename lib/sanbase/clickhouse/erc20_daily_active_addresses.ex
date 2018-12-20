defmodule Sanbase.Clickhouse.Erc20DailyActiveAddresses do
  @moduledoc ~s"""
  Uses ClickHouse to calculate the daily active addresses for an ERC20 token

  Note: Experimental. Define the schema but do not use it now.
  """

  use Ecto.Schema

  alias Sanbase.DateTimeUtils

  require Sanbase.ClickhouseRepo, as: ClickhouseRepo

  @table "erc20_daily_active_addresses"

  @primary_key false
  @timestamps_opts updated_at: false
  schema "erc20_daily_active_addresses" do
    field(:dt, :utc_datetime, primary_key: true)
    field(:contract, :string, primary_key: true)
    field(:total_addresses, :integer)
  end

  def changeset(_, _attrs \\ %{}) do
    raise "Should not try to change eth daily active addresses"
  end

  def active_addresses(contract, from, to) do
    from_datetime_unix = DateTime.to_unix(from)
    to_datetime_unix = DateTime.to_unix(to)

    query = """
    SELECT sum(total_addresses) as active_addresses
    FROM #{@table}
    PREWHERE contract = ?1 and
    dt >= toDateTime(?2) and
    dt <= toDateTime(?3)
    group by dt
    order by dt
    """

    args = [contract, from_datetime_unix, to_datetime_unix]

    ClickhouseRepo.query_transform(query, args, fn [active_addresses] ->
      [active_addresses |> String.to_integer()]
    end)
    |> case do
      {:ok, []} -> {:ok, 0}
      {:ok, active_addresses} -> {:ok, active_addresses |> List.first()}
    end
  end

  def active_addresses(contract, from, to, interval) do
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
      FROM erc20_daily_active_addresses
      PREWHERE contract = ?3 and
      dt >= toDateTime(?4) and
      dt <= toDateTime(?5)
      group by time
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

  def realtime_active_addresses(contract) do
    query = """
    SELECT toUnixTimestamp(dt), uniq(address) as total_addresses
    FROM erc20_daily_active_addresses_list
    WHERE contract = ?1 AND
    dt >= toDateTime(today())
    GROUP BY dt
    """

    args = [contract]

    ClickhouseRepo.query_transform(query, args, fn [dt, active_addresses] ->
      %{
        datetime: DateTime.from_unix!(dt),
        active_addresses: active_addresses |> String.to_integer()
      }
    end)
  end
end
