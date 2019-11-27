defmodule Sanbase.Clickhouse.HistoricalBalance do
  @moduledoc ~s"""
  Module providing functions for historical balances and balance changes.
  This module dispatches to underlaying modules and serves as common interface
  for many different database tables and schemas.
  """

  use AsyncWith
  @async_with_timeout 29_000

  alias Sanbase.Model.Project

  alias Sanbase.Clickhouse.HistoricalBalance.{
    BchBalance,
    BnbBalance,
    BtcBalance,
    EosBalance,
    Erc20Balance,
    EthBalance,
    LtcBalance,
    XrpBalance
  }

  @type slug :: String.t()

  @type address :: String.t()

  @typedoc ~s"""
  An interval represented as string. It has the format of number followed by one of:
  ns, ms, s, m, h, d or w - each representing some time unit
  """
  @type interval :: String.t()

  @typedoc ~s"""
  The type returned by the historical_balance/5 function
  """
  @type historical_balance_return ::
          {:ok, []}
          | {:ok, list(%{datetime: DateTime.t(), balance: number()})}
          | {:error, String.t()}

  @doc ~s"""
  Return a list of the assets that a given address currently holds or
  has held in the past.

  This can be combined with the historical balance query to see the historical
  balance of all currently owned assets
  """
  @spec assets_held_by_address(address) :: {:ok, list(slug)} | {:error, String.t()}
  def assets_held_by_address(address) do
    async with {:ok, erc20_assets} <- Erc20Balance.assets_held_by_address(address),
               {:ok, ethereum} <- EthBalance.assets_held_by_address(address) do
      {:ok, ethereum ++ erc20_assets}
    else
      error ->
        error
    end
  end

  @doc ~s"""
  For a given address or list of addresses returns the `slug` balance change for the
  from-to period. The returned lists indicates the address, before balance, after balance
  and the balance change
  """
  def balance_change(selector, address, from, to) do
    infrastructure = Map.fetch!(selector, :infrastructure)
    slug = Map.get(selector, :slug)

    case {infrastructure, slug} do
      {"ETH", "ethereum"} ->
        with {:ok, contract, decimals} <- Project.contract_info_by_slug("ethereum"),
             do: EthBalance.balance_change(address, contract, decimals, from, to)

      {"ETH", _} ->
        with {:ok, contract, decimals} <- Project.contract_info_by_slug(slug || "ethereum"),
             do: Erc20Balance.balance_change(address, contract, decimals, from, to)

      {"XRP", _} ->
        currency = Map.get(selector, :currency, "XRP")
        XrpBalance.balance_change(address, currency, 0, from, to)

      {"BTC", _} ->
        with {:ok, contract, decimals} <- Project.contract_info_by_slug("bitcoin"),
             do: BtcBalance.balance_change(address, contract, decimals, from, to)

      {"BCH", _} ->
        with {:ok, contract, decimals} <- Project.contract_info_by_slug("bitcoin-cash"),
             do: BchBalance.balance_change(address, contract, decimals, from, to)

      {"LTC", _} ->
        with {:ok, contract, decimals} <- Project.contract_info_by_slug("litecoin"),
             do: LtcBalance.balance_change(address, contract, decimals, from, to)

      {"EOS", _} ->
        with {:ok, contract, decimals} <- Project.contract_info_by_slug(slug || "eos"),
             do: EosBalance.balance_change(address, contract, decimals, from, to)

      {"BNB", _} ->
        with {:ok, contract, decimals} <- Project.contract_info_by_slug(slug || "binance-coin"),
             do: BnbBalance.balance_change(address, contract, decimals, from, to)
    end
  end

  @doc ~s"""
  For a given address or list of addresses returns the combined `slug` balance for each bucket
  of size `interval` in the from-to time period
  """

  def historical_balance(selector, address, from, to, interval) do
    infrastructure = Map.fetch!(selector, :infrastructure)
    slug = Map.get(selector, :slug)

    case {infrastructure, slug} do
      {"ETH", ethereum} when ethereum in [nil, "ethereum"] ->
        with {:ok, contract, decimals} <- Project.contract_info_by_slug("ethereum"),
             do: EthBalance.historical_balance(address, contract, decimals, from, to, interval)

      {"ETH", _} ->
        with {:ok, contract, decimals} <- Project.contract_info_by_slug(slug),
             do: Erc20Balance.historical_balance(address, contract, decimals, from, to, interval)

      {"XRP", _} ->
        currency = Map.get(selector, :currency, "XRP")
        XrpBalance.historical_balance(address, currency, 0, from, to, interval)

      {"BTC", _} ->
        with {:ok, contract, decimals} <- Project.contract_info_by_slug("bitcoin"),
             do: BtcBalance.historical_balance(address, contract, decimals, from, to, interval)

      {"BCH", _} ->
        with {:ok, contract, decimals} <- Project.contract_info_by_slug("bitcoin-cash"),
             do: BchBalance.historical_balance(address, contract, decimals, from, to, interval)

      {"LTC", _} ->
        with {:ok, contract, decimals} <- Project.contract_info_by_slug("litecoin"),
             do: LtcBalance.historical_balance(address, contract, decimals, from, to, interval)

      {"EOS", _} ->
        with {:ok, contract, decimals} <- Project.contract_info_by_slug(slug || "eos"),
             do: EosBalance.historical_balance(address, contract, decimals, from, to, interval)

      {"BNB", _} ->
        with {:ok, contract, decimals} <- Project.contract_info_by_slug(slug || "binance-coin"),
             do: BnbBalance.historical_balance(address, contract, decimals, from, to, interval)
    end
  end
end
