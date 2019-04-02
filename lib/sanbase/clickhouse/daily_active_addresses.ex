defmodule Sanbase.Clickhouse.DailyActiveAddresses do
  @moduledoc ~s"""
  Dispatch the calculations of the daily active addresses to the correct module
  """
  alias Sanbase.Clickhouse.Erc20DailyActiveAddresses, as: Erc20
  alias Sanbase.Clickhouse.EthDailyActiveAddresses, as: Eth

  @ethereum ["ethereum", "ETH"]

  def realtime_active_addresses(eth) when eth in @ethereum do
    Eth.realtime_active_addresses()
  end

  def realtime_active_addresses(contract) do
    Erc20.realtime_active_addresses(contract)
  end

  def average_active_addresses(eth, from, to) when eth in @ethereum do
    Eth.average_active_addresses(from, to)
  end

  def average_active_addresses(contract, from, to) do
    Erc20.average_active_addresses(contract, from, to)
  end

  def average_active_addresses(eth, from, to, interval) when eth in @ethereum do
    Eth.average_active_addresses(from, to, interval)
  end

  def average_active_addresses(contract, from, to, interval) do
    Erc20.average_active_addresses(contract, from, to, interval)
  end
end
