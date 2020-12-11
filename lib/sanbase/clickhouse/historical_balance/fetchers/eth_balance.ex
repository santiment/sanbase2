defmodule Sanbase.Clickhouse.HistoricalBalance.EthBalance do
  @doc ~s"""
  Module for working with historical Ethereum balances.
  """

  @behaviour Sanbase.Clickhouse.HistoricalBalance.Behaviour
  use Ecto.Schema

  import Sanbase.Clickhouse.HistoricalBalance.Utils

  alias Sanbase.ClickhouseRepo

  @eth_decimals 1_000_000_000_000_000_000

  @table "eth_balances"
  schema @table do
    field(:datetime, :utc_datetime, source: :dt)
    field(:address, :string, source: :to)
    field(:value, :float)
    field(:sign, :integer)
  end

  @doc false
  @spec changeset(any(), any()) :: no_return()
  def changeset(_, _),
    do: raise("Should not try to change eth balances")

  @impl Sanbase.Clickhouse.HistoricalBalance.Behaviour
  def assets_held_by_address(address) do
    {query, args} = asset_held_by_address_query(address)

    ClickhouseRepo.query_transform(query, args, fn [value] ->
      %{
        slug: "ethereum",
        balance: value / @eth_decimals
      }
    end)
  end

  @impl Sanbase.Clickhouse.HistoricalBalance.Behaviour
  def current_balance(addresses, "ETH", _decimals) do
    {query, args} = current_balance_query(addresses)

    ClickhouseRepo.query_transform(query, args, fn [address, value] ->
      %{
        address: address,
        balance: value / @eth_decimals
      }
    end)
  end

  @impl Sanbase.Clickhouse.HistoricalBalance.Behaviour
  def historical_balance([], _, _, _, _, _), do: {:ok, []}

  @impl Sanbase.Clickhouse.HistoricalBalance.Behaviour
  def historical_balance(addresses, currency, decimals, from, to, interval)
      when is_list(addresses) do
    combine_historical_balances(addresses, fn address ->
      historical_balance(address, currency, decimals, from, to, interval)
    end)
  end

  @impl Sanbase.Clickhouse.HistoricalBalance.Behaviour
  def historical_balance(address, _currency, _decimals, from, to, interval)
      when is_binary(address) do
    address = String.downcase(address)
    {query, args} = historical_balance_query(address, from, to, interval)

    ClickhouseRepo.query_transform(query, args, fn [dt, value, has_changed] ->
      %{
        datetime: DateTime.from_unix!(dt),
        balance: value / @eth_decimals,
        has_changed: has_changed
      }
    end)
    |> maybe_update_first_balance(fn -> last_balance_before(address, "ETH", 18, from) end)
    |> maybe_fill_gaps_last_seen_balance()
  end

  @impl Sanbase.Clickhouse.HistoricalBalance.Behaviour
  def balance_change([], _, _, _, _), do: {:ok, []}

  @impl Sanbase.Clickhouse.HistoricalBalance.Behaviour
  def balance_change(address_or_addresses, _currency, _decimals, from, to)
      when is_binary(address_or_addresses) or is_list(address_or_addresses) do
    {query, args} = balance_change_query(address_or_addresses, from, to)

    ClickhouseRepo.query_transform(query, args, fn
      [address, balance_start, balance_end, balance_change] ->
        %{
          address: address,
          balance_start: balance_start / @eth_decimals,
          balance_end: balance_end / @eth_decimals,
          balance_change_amount: balance_change / @eth_decimals,
          balance_change_percent: Sanbase.Math.percent_change(balance_start, balance_end)
        }
    end)
  end

  @impl Sanbase.Clickhouse.HistoricalBalance.Behaviour
  def historical_balance_change([], _, _, _, _, _), do: {:ok, []}

  def historical_balance_change(address_or_addresses, _currency, _decimals, from, to, interval)
      when is_binary(address_or_addresses) or is_list(address_or_addresses) do
    {query, args} = historical_balance_change_query(address_or_addresses, from, to, interval)

    ClickhouseRepo.query_transform(query, args, fn [dt, change] ->
      %{
        datetime: DateTime.from_unix!(dt),
        balance_change: change / @eth_decimals
      }
    end)
  end

  @impl Sanbase.Clickhouse.HistoricalBalance.Behaviour
  def last_balance_before(address, _currency, _decimals, datetime) do
    query = """
    SELECT value
    FROM #{@table}
    PREWHERE
      address = ?1 AND
      dt <=toDateTime(?2) AND
      sign = 1
    ORDER BY dt desc
    LIMIT 1
    """

    args = [address, DateTime.to_unix(datetime)]

    case ClickhouseRepo.query_transform(query, args, & &1) do
      {:ok, [[balance]]} -> {:ok, balance / @eth_decimals}
      {:ok, []} -> {:ok, 0}
      {:error, error} -> {:error, error}
    end
  end

  # Private functions

  defp asset_held_by_address_query(address) do
    query = """
    SELECT value
    FROM #{@table}
    PREWHERE
      address = ?1 AND
      sign = 1
    ORDER BY dt DESC
    LIMIT 1
    """

    args = [address |> String.downcase()]
    {query, args}
  end

  defp current_balance_query(addresses) do
    query = """
    SELECT address, argMax(value, dt)
    FROM #{@table}
    PREWHERE
      address IN (?1) AND
      sign = 1
    GROUP BY address
    """

    addresses = Enum.map(addresses, &String.downcase/1)
    args = [addresses]

    {query, args}
  end

  defp historical_balance_query(address, from, to, interval) when is_binary(address) do
    interval = Sanbase.DateTimeUtils.str_to_sec(interval)
    from_unix = DateTime.to_unix(from)
    to_unix = DateTime.to_unix(to)
    span = div(to_unix - from_unix, interval) |> max(1)

    # The balances table is like a stack. For each balance change there is a record
    # with sign = -1 that is the old balance and with sign = 1 which is the new balance
    query = """
    SELECT time, SUM(value), toUInt8(SUM(has_changed))
      FROM (
        SELECT
          toUnixTimestamp(intDiv(toUInt32(?4 + number * ?1), ?1) * ?1) AS time,
          toFloat64(0) AS value,
          toInt8(0) AS has_changed
        FROM numbers(?2)

      UNION ALL

      SELECT
        toUnixTimestamp(intDiv(toUInt32(dt), ?1) * ?1) AS time,
        argMax(value, dt),
        toUInt8(1) AS has_changed
      FROM #{@table}
      PREWHERE
        address = ?3 AND
        sign = 1 AND
        dt >= toDateTime(?4) AND
        dt < toDateTime(?5)
      GROUP BY time
    )
    GROUP BY time
    ORDER BY time
    """

    args = [interval, span, address, from_unix, to_unix]
    {query, args}
  end

  defp balance_change_query(address_or_addresses, from, to) do
    addresses =
      address_or_addresses |> List.wrap() |> List.flatten() |> Enum.map(&String.downcase/1)

    query = """
    SELECT
      address,
      argMaxIf(value, dt, dt <= ?2 AND sign = 1) AS start_balance,
      argMaxIf(value, dt, dt <= ?3 AND sign = 1) AS end_balance,
      end_balance - start_balance AS diff
    FROM #{@table}
    PREWHERE
      address IN (?1)
    GROUP BY address
    """

    args = [addresses, from, to]

    {query, args}
  end

  defp historical_balance_change_query(address_or_addresses, from, to, interval) do
    addresses =
      address_or_addresses |> List.wrap() |> List.flatten() |> Enum.map(&String.downcase/1)

    interval = Sanbase.DateTimeUtils.str_to_sec(interval)
    to_unix = DateTime.to_unix(to)
    from_unix = DateTime.to_unix(from)
    span = div(to_unix - from_unix, interval) |> max(1)

    # The balances table is like a stack. For each balance change there is a record
    # with sign = -1 that is the old balance and with sign = 1 which is the new balance
    query = """
    SELECT time, SUM(change)
      FROM (
        SELECT
          toUnixTimestamp(intDiv(toUInt32(?4 + number * ?1), ?1) * ?1) AS time,
          toFloat64(0) AS change
        FROM numbers(?2)

      UNION ALL

      SELECT
        toUnixTimestamp(intDiv(toUInt32(dt), ?1) * ?1) AS time,
        sign*value AS change
      FROM #{@table} FINAL
      PREWHERE
        address in (?3) AND
        dt >= toDateTime(?4) AND
        dt <= toDateTime(?5)
      GROUP BY address, dt, value, sign
    )
    GROUP BY time
    ORDER BY time
    """

    args = [interval, span, addresses, from_unix, to_unix]
    {query, args}
  end
end
