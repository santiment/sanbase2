defmodule Sanbase.Clickhouse.HistoricalBalance.XrpBalance do
  @doc ~s"""
  Module for working with historical ethereum balances.

  Includes functions for calculating:
  - Historical balances for an address or a list of addresses. For a list of addresses
  the combined balance is returned
  - Balance changes for an address or a list of addresses. This is used to calculate
  ethereum spent over time. Summing the balance changes of all wallets of a project
  allows to easily handle transactions between project wallets and not count them
  as spent.
  """

  @behaviour Sanbase.Clickhouse.HistoricalBalance.Behaviour
  use Ecto.Schema

  import Sanbase.Clickhouse.HistoricalBalance.Utils

  require Sanbase.ClickhouseRepo, as: ClickhouseRepo

  @table "eth_balances"
  schema @table do
    field(:datetime, :utc_datetime, source: :dt)
    field(:address, :string, source: :to)
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
    {query, args} = current_ethereum_balance_query(address)

    ClickhouseRepo.query_transform(query, args, fn [value] ->
      %{
        slug: "ethereum",
        balance: value
      }
    end)
  end

  @impl Sanbase.Clickhouse.HistoricalBalance.Behaviour
  def historical_balance(addr, _currency, _decimals, from, to, interval) when is_binary(addr) do
    {query, args} = historical_balance_query(addr, from, to, interval)

    ClickhouseRepo.query_transform(query, args, fn [dt, value, has_changed] ->
      %{
        datetime: DateTime.from_unix!(dt),
        balance: value,
        has_changed: has_changed
      }
    end)
    |> case do
      {:ok, result} ->
        result =
          result
          |> fill_gaps_last_seen_balance()
          |> Enum.drop_while(fn %{datetime: dt} -> DateTime.compare(dt, from) == :lt end)

        {:ok, result}

      error ->
        error
    end
  end

  @impl Sanbase.Clickhouse.HistoricalBalance.Behaviour
  def historical_balance(addresses, currency, decimals, from, to, interval)
      when is_list(addresses) do
    result =
      addresses
      |> Sanbase.Parallel.map(fn address ->
        {:ok, balances} = historical_balance(address, currency, decimals, from, to, interval)
        balances
      end)
      |> Enum.zip()
      |> Enum.map(&Tuple.to_list/1)
      |> Enum.map(fn
        [] ->
          []

        [%{datetime: datetime} | _] = list ->
          balance = list |> Enum.map(& &1.balance) |> Enum.sum()
          %{datetime: datetime, balance: balance}
      end)

    {:ok, result}
  end

  @impl Sanbase.Clickhouse.HistoricalBalance.Behaviour
  def balance_change([], _, _, _, _), do: {:ok, []}

  @impl Sanbase.Clickhouse.HistoricalBalance.Behaviour
  def balance_change(address_or_addresses, _currency, _decimals, from, to)
      when is_binary(address_or_addresses) or is_list(address_or_addresses) do
    {query, args} = balance_change_query(address_or_addresses, from, to)

    ClickhouseRepo.query_transform(query, args, fn [address, start_balance, end_balance, change] ->
      {address, {start_balance, end_balance, change}}
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
        balance_change: change
      }
    end)
    |> case do
      {:ok, result} ->
        result =
          result
          |> Enum.drop_while(fn %{datetime: dt} -> DateTime.compare(dt, from) == :lt end)

        {:ok, result}

      error ->
        error
    end
  end

  # Private functions

  defp current_ethereum_balance_query(address) do
    query = """
    SELECT value
    FROM
      #{@table}
    PREWHERE
      address = ?1 AND
      sign = 1
    ORDER BY dt DESC
    LIMIT 1
    """

    args = [address |> String.downcase()]
    {query, args}
  end

  @first_datetime ~U[2015-07-29 00:00:00Z] |> DateTime.to_unix()
  defp historical_balance_query(address, _from, to, interval) when is_binary(address) do
    address = String.downcase(address)
    interval = Sanbase.DateTimeUtils.str_to_sec(interval)
    to_unix = DateTime.to_unix(to)
    span = div(to_unix - @first_datetime, interval) |> max(1)

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
        dt <= toDateTime(?5)
      GROUP BY time
    )
    GROUP BY time
    ORDER BY time
    """

    args = [interval, span, address, @first_datetime, to_unix]
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
      FROM #{@table}
      PREWHERE
        address in (?3) AND
        dt >= toDateTime(?4) AND
        dt <= toDateTime(?5)
      GROUP BY address, value, dt, sign
    )
    GROUP BY time
    ORDER BY time
    """

    args = [interval, span, addresses, from_unix, to_unix]
    {query, args}
  end
end
