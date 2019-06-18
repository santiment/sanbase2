defmodule Sanbase.Clickhouse.HistoricalBalance do
  @moduledoc ~s"""
  Module providing functions for historical balances, balance changes, ethereum/token
  spent. This module dispatches to underlaying modules and serves as common interface
  for many different database tables and schemas.
  """

  alias Sanbase.Model.Project
  alias Sanbase.Clickhouse.HistoricalBalance.{EthBalance, Erc20Balance}

  @type slug :: String.t()

  @type address :: String.t()

  @typedoc ~s"""
  An interval represented as string. It has the format of number followed by one of:
  ns, ms, s, m, h, d or w - each representing some time unit
  """
  @type interval :: String.t()

  @doc ~s"""
  Return a list of the assets that a given address currently holds or
  has held in the past.

  This can be combined with the historical balance query to see the historical
  balance of all currently owned assets
  """
  @spec assets_held_by_address(address) :: list(slug)
  def assets_held_by_address(address) do
    with {:ok, erc20_assets} <- Erc20Balance.assets_held_by_address(address),
         {:ok, ethereum} <- EthBalance.assets_held_by_address(address) do
      {:ok, ethereum ++ erc20_assets}
    end
  end

  @doc ~s"""
  For a given address or list of addresses returns the ethereum balance change for the
  from-to period. The returned lists indicates the address, before balance, after balance
  and the balance change.

  This is special case of balance_change/4 but as ethereum is used a lot for calculating
  ethereum spent this case avoids a call to the database to obtain the contract
  """
  @spec eth_balance_change(address | list(address), DateTime.t(), DateTime.t()) ::
          {:ok, list({address, {balance_before, balance_after, balance_change}})}
          | {:error, String.t()}
        when balance_before: number(), balance_after: number(), balance_change: number()
  def eth_balance_change(addresses, from, to) do
    EthBalance.balance_change(addresses, from, to)
  end

  @doc ~s"""
  For a given address or list of addresses returns the ethereum  balance change for each bucket
  of size `interval` in the from-to time period
  """
  @spec eth_balance_change(address | list(address), DateTime.t(), DateTime.t(), interval) ::
          {:ok, list({address, %{datetime: DateTime.t(), balance_change: number()}})}
          | {:error, String.t()}
  def eth_balance_change(addresses, from, to, interval) do
    EthBalance.balance_change(addresses, from, to, interval)
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
    with {:ok, contract, token_decimals} <- Project.contract_info_by_slug(slug) do
      case contract do
        "ETH" ->
          EthBalance.balance_change(address, from, to)

        _ ->
          Erc20Balance.balance_change(address, contract, token_decimals, from, to)
      end
    else
      {:error, error} -> {:error, inspect(error)}
    end
  end

  @doc ~s"""
  For a given address or list of addresses returns the combined `slug` balance for each bucket
  of size `interval` in the from-to time period
  """
  @spec historical_balance(address | list(address), slug, DateTime.t(), DateTime.t(), interval) ::
          {:ok, list({address, %{datetime: DateTime.t(), balance: number()}})}
          | {:error, String.t()}
  def historical_balance(address, slug, from, to, interval) do
    with {:ok, contract, token_decimals} <- Project.contract_info_by_slug(slug) do
      case contract do
        "ETH" ->
          EthBalance.historical_balance(address, from, to, interval)

        _ ->
          Erc20Balance.historical_balance(address, contract, token_decimals, from, to, interval)
      end
    else
      {:error, error} -> {:error, inspect(error)}
    end
  end

  @doc ~s"""
  For a given address or list of addresses calculate the ethereum spent.
  Ethereum spent is defined as follows:
    - If the combined balance of the addresses at `from` datetime is bigger than
    the combined balance at `to` datetime, the eth spent is the absolute value
    of the difference between the two balance
    - Zero otherwise
  """
  @spec eth_spent(address | list(address), DateTime.t(), DateTime.t()) ::
          {:ok, number()} | {:error, String.t()}
  def eth_spent(addresses, from, to) do
    with {:ok, balance_changes} <- eth_balance_change(addresses, from, to) do
      eth_spent =
        balance_changes
        |> Enum.map(fn {_, {_, _, change}} -> change end)
        |> Enum.sum()
        |> case do
          change when change < 0 -> abs(change)
          _ -> 0
        end

      {:ok, eth_spent}
    end
  end

  @doc ~s"""
  For a given address or list of addresses calculate the ethereum spent.
  Ethereum spent is defined as follows:
    - If the combined balance of the addresses decreases compared to the previous
    time bucket, the absolute value of the change is the ethereum spent
    - If the combined balance of the addresses increases compared to the previous
    time bucket, the ethereum spent is equal to 0
  """
  @spec eth_spent_over_time(address | list(address), DateTime.t(), DateTime.t(), interval) ::
          {:ok, list(%{datetime: DateTime.t(), eth_spent: number})}
          | {:error, String.t()}
  def eth_spent_over_time(addresses, from, to, interval)
      when is_binary(addresses) or is_list(addresses) do
    with {:ok, balance_changes} <- eth_balance_change(addresses, from, to, interval) do
      eth_spent_over_time =
        balance_changes
        |> Enum.map(fn
          %{balance_change: change, datetime: dt} when change < 0 ->
            %{datetime: dt, eth_spent: abs(change)}

          %{datetime: dt} ->
            %{datetime: dt, eth_spent: 0}
        end)

      {:ok, eth_spent_over_time}
    end
  end
end
