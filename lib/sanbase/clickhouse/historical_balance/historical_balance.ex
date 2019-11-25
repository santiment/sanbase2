defmodule Sanbase.Clickhouse.HistoricalBalance do
  @moduledoc ~s"""
  Module providing functions for historical balances, balance changes, ethereum/token
  spent. This module dispatches to underlaying modules and serves as common interface
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
  @spec balance_change(address | list(address), slug, DateTime.t(), DateTime.t()) ::
          {:ok, list({address, {balance_before, balance_after, balance_change}})}
          | {:error, String.t()}
        when balance_before: number(), balance_after: number(), balance_change: number()
  def balance_change(address, slug, from, to) do
    case Project.contract_info_by_slug(slug) do
      {:ok, contract, decimals} ->
        case contract do
          "ETH" ->
            EthBalance.balance_change(address, contract, decimals, from, to)

          "XRP" ->
            XrpBalance.balance_change(address, contract, decimals, from, to)

          "BTC" ->
            BtcBalance.balance_change(address, contract, decimals, from, to)

          "BCH" ->
            BchBalance.balance_change(address, contract, decimals, from, to)

          "LTC" ->
            LtcBalance.balance_change(address, contract, decimals, from, to)

          "eosio.token/EOS" ->
            EosBalance.balance_change(address, contract, decimals, from, to)

          "BNB" ->
            BnbBalance.balance_change(address, contract, decimals, from, to)

          <<"0x", _rest::binary>> = contract ->
            Erc20Balance.balance_change(address, contract, decimals, from, to)
        end

      {:error, error} ->
        {:error, inspect(error)}
    end
  end

  @doc ~s"""
  For a given address or list of addresses returns the combined `slug` balance for each bucket
  of size `interval` in the from-to time period
  """
  @spec historical_balance(address | list(address), slug, DateTime.t(), DateTime.t(), interval) ::
          historical_balance_return
  def historical_balance(address, slug, from, to, interval) do
    case Project.contract_info_by_slug(slug) do
      {:ok, contract, decimals} ->
        case contract do
          "ETH" ->
            EthBalance.historical_balance(address, contract, decimals, from, to, interval)

          "XRP" ->
            XrpBalance.historical_balance(address, contract, decimals, from, to, interval)

          "BTC" ->
            BtcBalance.historical_balance(address, contract, decimals, from, to, interval)

          "BCH" ->
            BchBalance.historical_balance(address, contract, decimals, from, to, interval)

          "LTC" ->
            LtcBalance.historical_balance(address, contract, decimals, from, to, interval)

          "eosio.token/EOS" ->
            EosBalance.historical_balance(address, contract, decimals, from, to, interval)

          "BNB" ->
            BnbBalance.historical_balance(address, contract, decimals, from, to, interval)

          <<"0x", _rest::binary>> = contract ->
            Erc20Balance.balance_change(address, contract, decimals, from, to)
        end

      {:error, error} ->
        {:error, inspect(error)}
    end
  end
end
