defmodule Sanbase.Clickhouse.DailyActiveAddresses do
  @moduledoc ~s"""
  Dispatch the calculations of the daily active addresses to the correct module
  """
  alias Sanbase.Clickhouse.Bitcoin
  alias Sanbase.Clickhouse.Erc20DailyActiveAddresses, as: Erc20
  alias Sanbase.Clickhouse.EthDailyActiveAddresses, as: Eth

  require Logger

  @ethereum ["ethereum", "ETH"]
  @bitcoin ["bitcoin", "BTC"]

  def realtime_active_addresses(eth) when is_binary(eth) and eth in @ethereum do
    Eth.realtime_active_addresses()
  end

  def realtime_active_addresses(contract) do
    Erc20.realtime_active_addresses(contract)
  end

  def average_active_addresses(eth, from, to) when is_binary(eth) and eth in @ethereum do
    Eth.average_active_addresses(from, to)
  end

  def average_active_addresses(eth, from, to, interval)
      when is_binary(eth) and eth in @ethereum do
    Eth.average_active_addresses(from, to, interval)
  end

  def average_active_addresses(contract, from, to, interval) when is_binary(contract) do
    Erc20.average_active_addresses(contract, from, to, interval)
  end

  def average_active_addresses(contracts, from, to) when is_list(contracts) do
    {btc, eth, erc20} =
      contracts
      |> Enum.reduce({[], [], []}, fn
        c, {btc, eth, erc20} when c in @bitcoin -> {[c | btc], eth, erc20}
        c, {btc, eth, erc20} when c in @ethereum -> {btc, [c | eth], erc20}
        c, {btc, eth, erc20} when is_binary(c) -> {btc, eth, [c | erc20]}
        _, acc -> acc
      end)

    with {:ok, btc_average_addresses} <- do_btc_average_active_addresses(btc, from, to),
         {:ok, eth_average_addresses} <- do_eth_average_active_addresses(eth, from, to),
         {:ok, erc20_average_addresses} <- do_erc20_average_active_addresses(erc20, from, to) do
      {:ok, btc_average_addresses ++ eth_average_addresses ++ erc20_average_addresses}
    end
  end

  # Helper functions that return lists of {slug, average_active_addresses}
  # As Ethereum and Bitcoin do not have contracts they are simulated
  # In case of error return `{:ok, []}` because the other 2 queries could succeed
  # and return meaningful results
  defp do_btc_average_active_addresses([], _, _), do: {:ok, []}

  defp do_btc_average_active_addresses([_ | _], from, to) do
    with {:ok, result} <- Bitcoin.average_active_addresses(from, to) do
      {:ok, [{"BTC", result}]}
    else
      {:error, error} ->
        Logger.warn("Cannot fetch average active addresses for Bitcoin")
        {:ok, []}
    end
  end

  defp do_eth_average_active_addresses([], _, _), do: {:ok, []}

  defp do_eth_average_active_addresses([_ | _], from, to) do
    with {:ok, result} <- Eth.average_active_addresses(from, to) do
      {:ok, [{"ETH", result}]}
    else
      {:error, error} ->
        Logger.warn("Cannot fetch average active addresses for Ethereum")
        {:ok, []}
    end
  end

  defp do_erc20_average_active_addresses([], _, _), do: {:ok, []}

  defp do_erc20_average_active_addresses(contracts, from, to) do
    with {:ok, result} <- Erc20.average_active_addresses(contracts, from, to) do
      {:ok, result}
    else
      {:error, error} ->
        Logger.warn("Cannot fetch average active addresses for ERC20 contracts")
        {:ok, []}
    end
  end
end
