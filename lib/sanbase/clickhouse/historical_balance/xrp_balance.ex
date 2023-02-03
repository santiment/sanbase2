defmodule Sanbase.Clickhouse.HistoricalBalance.XrpBalance do
  @doc ~s"""
  Module for working with historical XRP balances.
  """

  @behaviour Sanbase.Clickhouse.HistoricalBalance.Behaviour
  use Ecto.Schema

  import Sanbase.Clickhouse.HistoricalBalance.Utils

  alias Sanbase.ClickhouseRepo

  @table "xrp_balances"
  schema @table do
    field(:datetime, :utc_datetime, source: :dt)
    field(:balance, :float)
    field(:old_balance, :float, source: :oldBalance)
    field(:address, :string)
    field(:currency, :string)
  end

  @doc false
  @spec changeset(any(), any()) :: no_return()
  def changeset(_, _),
    do: raise("Should not try to change xrp balances")

  @impl Sanbase.Clickhouse.HistoricalBalance.Behaviour
  def assets_held_by_address(address) do
    {query, args} = current_balances_query([address], "XRP")

    ClickhouseRepo.query_transform(query, args, fn [^address, value] ->
      %{
        slug: "xrp",
        balance: value
      }
    end)
  end

  @impl Sanbase.Clickhouse.HistoricalBalance.Behaviour
  def current_balance(addresses, _currency, _decimals) do
    {query, args} = current_balances_query(addresses, "XRP")

    ClickhouseRepo.query_transform(query, args, fn [address, value] ->
      %{
        address: address,
        balance: value
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
  def historical_balance(address, currency, _decimals, from, to, interval)
      when is_binary(address) do
    {query, args} = historical_balance_query(address, currency, from, to, interval)

    ClickhouseRepo.query_transform(query, args, fn [dt, balance, has_changed] ->
      %{
        datetime: DateTime.from_unix!(dt),
        balance: balance,
        has_changed: has_changed
      }
    end)
    |> maybe_update_first_balance(fn -> last_balance_before(address, currency, 0, from) end)
    |> maybe_fill_gaps_last_seen_balance()
  end

  @impl Sanbase.Clickhouse.HistoricalBalance.Behaviour
  def balance_change([], _, _, _, _), do: {:ok, []}

  @impl Sanbase.Clickhouse.HistoricalBalance.Behaviour
  def balance_change(address_or_addresses, currency, _decimals, from, to)
      when is_binary(address_or_addresses) or is_list(address_or_addresses) do
    {query, args} = balance_change_query(address_or_addresses, currency, from, to)

    ClickhouseRepo.query_transform(query, args, fn
      [address, balance_start, balance_end, balance_change] ->
        %{
          address: address,
          balance_start: balance_start,
          balance_end: balance_end,
          balance_change_amount: balance_change,
          balance_change_percent: Sanbase.Math.percent_change(balance_start, balance_end)
        }
    end)
  end

  @impl Sanbase.Clickhouse.HistoricalBalance.Behaviour
  def historical_balance_change([], _, _, _, _, _), do: {:ok, []}

  def historical_balance_change(address_or_addresses, currency, _decimals, from, to, interval)
      when is_binary(address_or_addresses) or is_list(address_or_addresses) do
    {query, args} =
      historical_balance_change_query(address_or_addresses, currency, from, to, interval)

    ClickhouseRepo.query_transform(query, args, fn [dt, change] ->
      %{
        datetime: DateTime.from_unix!(dt),
        balance_change: change
      }
    end)
  end

  @impl Sanbase.Clickhouse.HistoricalBalance.Behaviour
  def last_balance_before(address, currency, _decimals, datetime) do
    query = """
    SELECT balance
    FROM #{@table}
    PREWHERE
      address = ?1 AND
      currency = ?2 AND
      dt <=toDateTime(?3)
    ORDER BY dt DESC
    LIMIT 1
    """

    args = [address, currency, DateTime.to_unix(datetime)]

    case ClickhouseRepo.query_transform(query, args, & &1) do
      {:ok, [[balance]]} -> {:ok, balance}
      {:ok, []} -> {:ok, 0}
      {:error, error} -> {:error, error}
    end
  end

  # Private functions

  defp current_balances_query(address, currency) do
    query = """
    SELECT address, argMax(value, dt)
    FROM #{@table}
    PREWHERE
      address = ?1 AND
      currency = ?2 AND
      sign = 1
    GROUP BY address
    """

    args = [address, currency]
    {query, args}
  end

  defp historical_balance_query(address, currency, from, to, interval) when is_binary(address) do
    interval = Sanbase.DateTimeUtils.str_to_sec(interval)
    from_unix = DateTime.to_unix(from)
    to_unix = DateTime.to_unix(to)
    span = div(to_unix - from_unix, interval) |> max(1)

    # The balances table is like a stack. For each balance change there is a record
    # with sign = -1 that is the old balance and with sign = 1 which is the new balance
    query = """
    SELECT time, SUM(balance), toUInt8(SUM(has_changed))
      FROM (
        SELECT
          toUnixTimestamp(intDiv(toUInt32(?4 + number * ?1), ?1) * ?1) AS time,
          toFloat64(0) AS balance,
          toInt8(0) AS has_changed
        FROM numbers(?2)

      UNION ALL

      SELECT
        toUnixTimestamp(intDiv(toUInt32(dt), ?1) * ?1) AS time,
        argMax(balance, dt) AS balance,
        toUInt8(1) AS has_changed
      FROM #{@table}
      PREWHERE
        address = ?3 AND
        dt >= toDateTime(?4) AND
        dt < toDateTime(?5) AND
        currency = ?6
      GROUP BY time
    )
    GROUP BY time
    ORDER BY time
    """

    args = [interval, span, address, from_unix, to_unix, currency]
    {query, args}
  end

  defp balance_change_query(address_or_addresses, currency, from, to) do
    addresses = address_or_addresses |> List.wrap() |> List.flatten()

    query = """
    SELECT
      address,
      argMaxIf(balance, dt, dt <= ?3) AS start_balance,
      argMaxIf(balance, dt, dt <= ?4) AS end_balance,
      end_balance - start_balance AS diff
    FROM #{@table}
    PREWHERE
      address IN (?1) AND
      currency = ?2
    GROUP BY address
    """

    args = [addresses, currency, from, to]

    {query, args}
  end

  defp historical_balance_change_query(address_or_addresses, currency, from, to, interval) do
    addresses = address_or_addresses |> List.wrap() |> List.flatten()

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
          toUnixTimestamp(intDiv(toUInt32(?5 + number * ?1), ?1) * ?1) AS time,
          toFloat64(0) AS change
        FROM numbers(?2)

      UNION ALL

      SELECT
        toUnixTimestamp(intDiv(toUInt32(dt), ?1) * ?1) AS time,
        any(change) AS change
      FROM (
        SELECT dt, assetRefId, address, blockNumber, transactionIndex, (balance - oldBalance) AS change
        FROM xrp_balances
        PREWHERE
          address in (?3) AND
          currency = ?4 AND
          dt >= toDateTime(?5) AND
          dt <= toDateTime(?6)
      )
      GROUP BY assetRefId, address, dt, blockNumber, transactionIndex
    )
    GROUP BY time
    ORDER BY time
    """

    args = [interval, span, addresses, currency, from_unix, to_unix]
    {query, args}
  end
end
