defmodule Sanbase.Clickhouse.HistoricalBalance.LtcBalance do
  @doc ~s"""
  Module for working with historical Litecoin balances.
  """

  @behaviour Sanbase.Clickhouse.HistoricalBalance.Behaviour
  use Ecto.Schema

  import Sanbase.Clickhouse.HistoricalBalance.Utils
  import Sanbase.Clickhouse.HistoricalBalance.UtxoSqlQueries

  require Sanbase.ClickhouseRepo, as: ClickhouseRepo

  @table "ltc_balances"
  schema @table do
    field(:datetime, :utc_datetime, source: :dt)
    field(:balance, :float)
    field(:old_balance, :float, source: :oldBalance)
    field(:address, :string)
  end

  @doc false
  @spec changeset(any(), any()) :: no_return()
  def changeset(_, _),
    do: raise("Should not try to change ltc balances")

  @impl Sanbase.Clickhouse.HistoricalBalance.Behaviour
  def assets_held_by_address(address) do
    {query, args} = current_balance_query(@table, address)

    ClickhouseRepo.query_transform(query, args, fn [value] ->
      %{
        slug: "bitcoin",
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
  def historical_balance(address, currency, decimals, from, to, interval)
      when is_binary(address) do
    {query, args} = historical_balance_query(@table, address, from, to, interval)

    ClickhouseRepo.query_transform(query, args, fn [dt, balance, has_changed] ->
      %{
        datetime: DateTime.from_unix!(dt),
        balance: balance,
        has_changed: has_changed
      }
    end)
    |> maybe_update_first_balance(fn -> last_balance_before(address, currency, decimals, from) end)
    |> maybe_fill_gaps_last_seen_balance()
  end

  @impl Sanbase.Clickhouse.HistoricalBalance.Behaviour
  def balance_change([], _, _, _, _), do: {:ok, []}

  @impl Sanbase.Clickhouse.HistoricalBalance.Behaviour
  def balance_change(address_or_addresses, _currency, _decimals, from, to)
      when is_binary(address_or_addresses) or is_list(address_or_addresses) do
    {query, args} = balance_change_query(@table, address_or_addresses, from, to)

    ClickhouseRepo.query_transform(query, args, fn [address, start_balance, end_balance, change] ->
      {address, {start_balance, end_balance, change}}
    end)
  end

  @impl Sanbase.Clickhouse.HistoricalBalance.Behaviour
  def historical_balance_change([], _, _, _, _, _), do: {:ok, []}

  def historical_balance_change(address_or_addresses, _currency, _decimals, from, to, interval)
      when is_binary(address_or_addresses) or is_list(address_or_addresses) do
    {query, args} =
      historical_balance_change_query(@table, address_or_addresses, from, to, interval)

    ClickhouseRepo.query_transform(query, args, fn [dt, change] ->
      %{
        datetime: DateTime.from_unix!(dt),
        balance_change: change
      }
    end)
  end

  @impl Sanbase.Clickhouse.HistoricalBalance.Behaviour
  def last_balance_before(address, _currency, _decimals, datetime) do
    {query, args} = last_balance_before_query(@table, address, datetime)

    case ClickhouseRepo.query_transform(query, args, & &1) do
      {:ok, [[balance]]} -> {:ok, balance}
      {:ok, []} -> {:ok, 0}
      {:error, error} -> {:error, error}
    end
  end
end
