defmodule Sanbase.Clickhouse.HistoricalBalance.BnbBalance do
  @doc ~s"""
  Module for working with historical Binance balances.
  """

  @behaviour Sanbase.Clickhouse.HistoricalBalance.Behaviour
  use Ecto.Schema

  import Sanbase.Clickhouse.HistoricalBalance.Utils

  require Sanbase.ClickhouseRepo, as: ClickhouseRepo

  @table "bnb_balances"
  schema @table do
    field(:datetime, :utc_datetime, source: :dt)
    field(:currency, :string)
    field(:address, :string, source: :to)
    field(:value, :float)
    field(:sign, :integer)
  end

  @doc false
  @spec changeset(any(), any()) :: no_return()
  def changeset(_, _),
    do: raise("Should not try to change bnb balances")

  @impl Sanbase.Clickhouse.HistoricalBalance.Behaviour
  def assets_held_by_address(address) do
    {query, args} = assets_held_by_address_query(address)

    ClickhouseRepo.query_transform(query, args, fn [currency, balance] ->
      %{
        slug: currency,
        balance: balance
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
  def historical_balance(address, currency, decimals, from, to, interval) do
    {query, args} = historical_balance_query(address, currency, from, to, interval)

    ClickhouseRepo.query_transform(query, args, fn [dt, value, has_changed] ->
      %{
        datetime: Sanbase.DateTimeUtils.from_erl!(dt),
        balance: value,
        has_changed: has_changed
      }
    end)
    |> maybe_update_first_balance(fn -> last_balance_before(address, currency, decimals, from) end)
    |> maybe_fill_gaps_last_seen_balance()
  end

  @impl Sanbase.Clickhouse.HistoricalBalance.Behaviour
  def balance_change([], _, _, _, _), do: {:ok, []}

  def balance_change(addr, currency, token_decimals, from, to) do
    token_decimals = Sanbase.Math.ipow(10, token_decimals)

    query = """
    SELECT
      address,
      argMaxIf(value, dt, dt<=?3 AND sign = 1) AS start_balance,
      argMaxIf(value, dt, dt<=?4 AND sign = 1) AS end_balance,
      end_balance - start_balance AS diff
    FROM #{@table} FINAL
    PREWHERE
      address IN (?1) AND
      currency = ?2
    GROUP BY address
    """

    addresses = addr |> List.wrap()
    args = [addresses, currency, from, to]

    ClickhouseRepo.query_transform(query, args, fn [address, start_balance, end_balance, change] ->
      {address,
       {start_balance / token_decimals, end_balance / token_decimals, change / token_decimals}}
    end)
  end

  @impl Sanbase.Clickhouse.HistoricalBalance.Behaviour
  def last_balance_before(address, contract, _decimals, datetime) do
    query = """
    SELECT value
    FROM #{@table}
    PREWHERE
      address = ?1 AND
      currency = ?2 AND
      dt <=toDateTime(?3) AND
      sign = 1
    ORDER BY dt DESC
    LIMIT 1
    """

    args = [address, contract, DateTime.to_unix(datetime)]

    case ClickhouseRepo.query_transform(query, args, & &1) do
      {:ok, [[balance]]} -> {:ok, balance}
      {:ok, []} -> {:ok, 0}
      {:error, error} -> {:error, error}
    end
  end

  # Private functions

  defp historical_balance_query(address, currency, from, to, interval) do
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
          toDateTime(intDiv(toUInt32(?5 + number * ?1), ?1) * ?1) AS time,
          toFloat64(0) AS value,
          toUInt8(0) AS has_changed
        FROM numbers(?2)

    UNION ALL

    SELECT toDateTime(intDiv(toUInt32(dt), ?1) * ?1) AS time, argMax(value, dt), toUInt8(1) AS has_changed
      FROM #{@table}
      PREWHERE
        address = ?3 AND
        currency = ?4 AND
        sign = 1 AND
        dt >= toDateTime(?5) AND
        dt < toDateTime(?6)
      GROUP BY time
    )
    GROUP BY time
    ORDER BY time
    """

    args = [interval, span, address, currency, from_unix, to_unix]

    {query, args}
  end

  defp assets_held_by_address_query(address) do
    query = """
    SELECT
      contract,
      argMax(value, blockNumber)
    FROM
      #{@table}
    PREWHERE
      address = ?1 AND
      sign = 1
    GROUP BY contract
    """

    args = [address]

    {query, args}
  end
end
