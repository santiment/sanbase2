defmodule Sanbase.Clickhouse.HistoricalBalance.EthBalance do
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

  use Ecto.Schema

  import Sanbase.Clickhouse.HistoricalBalance.Utils

  require Sanbase.ClickhouseRepo, as: ClickhouseRepo

  @eth_decimals 1_000_000_000_000_000_000

  @typedoc ~s"""
  An interval represented as string. It has the format of number followed by one of:
  ns, ms, s, m, h, d or w - each representing some time unit
  """
  @type interval :: String.t()

  @type address :: String.t()

  @type historical_balance :: %{
          datetime: non_neg_integer(),
          balance: float()
        }

  @table "eth_balances"
  schema @table do
    field(:datetime, :utc_datetime, source: :dt)
    field(:address, :string, source: :to)
    field(:value, :float)
    field(:sign, :integer)
  end

  @doc false
  @spec changeset(any(), any()) :: no_return()
  def changeset(_, _attrs \\ %{}),
    do: raise("Should not try to change eth daily active addresses")

  @doc ~s"""
  For a given address or list of addresses returns the combined ethereum
  balance for each bucket of size `interval` in the from-to time period
  """
  @spec historical_balance(
          address | list(address),
          DateTime.t(),
          DateTime.t(),
          interval
        ) :: {:ok, list(historical_balance)} | {:error, String.t()}
  def historical_balance(addr, from, to, interval) do
    {query, args} = historical_balance_query(addr, from, to, interval)

    ClickhouseRepo.query_transform(query, args, fn [dt, value, has_changed] ->
      %{
        datetime: DateTime.from_unix!(dt),
        balance: value / @eth_decimals,
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

  @doc ~s"""
  For a given address or list of addresses returns the ethereum balance change for the
  from-to period. The returned lists indicates the address, before balance, after balance
  and the balance change
  """
  @spec balance_change(address | list(address), DateTime.t(), DateTime.t()) ::
          {:ok, list({address, {balance_before, balance_after, balance_change}})}
          | {:error, String.t()}
        when balance_before: number(), balance_after: number(), balance_change: number()
  def balance_change(addresses, from, to) when is_binary(addresses) or is_list(addresses) do
    {query, args} = balance_change_query(addresses, from, to)

    ClickhouseRepo.query_transform(query, args, fn [addr, s, e, change] ->
      {addr, {s / @eth_decimals, e / @eth_decimals, change / @eth_decimals}}
    end)
  end

  @doc ~s"""
  For a given address or list of addresses returns the ethereum  balance change for each bucket
  of size `interval` in the from-to time period
  """
  @spec balance_change(address | list(address), DateTime.t(), DateTime.t(), interval) ::
          {:ok, list({address, %{datetime: DateTime.t(), balance_change: number()}})}
          | {:error, String.t()}
  def balance_change(addresses, from, to, interval)
      when is_binary(addresses) or is_list(addresses) do
    {query, args} = balance_change_query(addresses, from, to, interval)

    ClickhouseRepo.query_transform(query, args, fn [dt, change] ->
      %{
        datetime: DateTime.from_unix!(dt),
        balance_change: change / @eth_decimals
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

  defp balance_change_query(addresses, from, to) do
    addresses = addresses |> List.wrap() |> List.flatten() |> Enum.map(&String.downcase/1)

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

  defp balance_change_query(addresses, from, to, interval) do
    addresses = Enum.map(addresses, &String.downcase/1)
    interval = Sanbase.DateTimeUtils.compound_duration_to_seconds(interval)
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

  @first_datetime ~N[2015-07-29 00:00:00] |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix()
  defp historical_balance_query(address, _from, to, interval) when is_binary(address) do
    address = String.downcase(address)
    interval = Sanbase.DateTimeUtils.compound_duration_to_seconds(interval)
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
        argMax(value, dt), toUInt8(1) AS has_changed
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

  defp historical_balance_query(addresses, _from, to, interval) when is_list(addresses) do
    addresses = Enum.map(addresses, &String.downcase/1)
    interval = Sanbase.DateTimeUtils.compound_duration_to_seconds(interval)
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
        SUM(value*sign),
        toUInt8(1) AS has_changed
      FROM #{@table}
      PREWHERE
        address in (?3) AND
        dt <= toDateTime(?5)
      GROUP BY time, address
    )
    GROUP BY time
    ORDER BY time
    """

    args = [interval, span, addresses, @first_datetime, to_unix]
    {query, args}
  end
end
