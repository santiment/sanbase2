defmodule Sanbase.Clickhouse.HistoricalBalance do
  @moduledoc ~s"""
  Module providing functions for historical balances, balance changes, ethereum/token
  spent. This module dispatches to underlaying modules and serves as common interface
  for many different database tables and schemas.
  """

  use AsyncWith
  @async_with_timeout 29_000

  alias Sanbase.Model.Project
  alias Sanbase.Clickhouse.HistoricalBalance.{EthBalance, Erc20Balance}

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
    EthBalance.balance_change(addresses, "ETH", 18, from, to)
  end

  @doc ~s"""
  For a given address or list of addresses returns the ethereum  balance change for each bucket
  of size `interval` in the from-to time period
  """
  @spec eth_balance_change(address | list(address), DateTime.t(), DateTime.t(), interval) ::
          {:ok, list({address, %{datetime: DateTime.t(), balance_change: number()}})}
          | {:error, String.t()}
  def eth_balance_change(addresses, from, to, interval) do
    EthBalance.historical_balance_change(addresses, "ETH", 18, from, to, interval)
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

          _ ->
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

          _ ->
            Erc20Balance.historical_balance(address, contract, decimals, from, to, interval)
        end

      {:error, error} ->
        {:error, inspect(error)}
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
    case eth_balance_change(addresses, from, to) do
      {:ok, balance_changes} ->
        eth_spent =
          balance_changes
          |> Enum.map(fn {_, {_, _, change}} -> change end)
          |> Enum.sum()
          |> case do
            change when change < 0 -> abs(change)
            _ -> 0
          end

        {:ok, eth_spent}

      {:error, error} ->
        {:error, error}
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
    case eth_balance_change(addresses, from, to, interval) do
      {:ok, balance_changes} ->
        eth_spent_over_time =
          balance_changes
          |> Enum.map(fn
            %{balance_change: change, datetime: dt} when change < 0 ->
              %{datetime: dt, eth_spent: abs(change)}

            %{datetime: dt} ->
              %{datetime: dt, eth_spent: 0}
          end)

        {:ok, eth_spent_over_time}

      {:error, error} ->
        {:error, error}
    end
  end
end
