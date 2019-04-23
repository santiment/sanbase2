defmodule Sanbase.Clickhouse.ShareOfDeposits do
  @moduledoc ~s"""
  Dispatch the calculations of share of deposits to the correct module
  """
  alias Sanbase.Clickhouse.Erc20ShareOfDeposits, as: Erc20
  alias Sanbase.Clickhouse.EthShareOfDeposits, as: Eth

  @ethereum ["ethereum", "ETH"]

  def first_datetime(slug) when slug in @ethereum do
    Eth.first_datetime(slug)
  end

  def first_datetime(contract) when is_binary(contract) do
    Erc20.first_datetime(contract)
  end

  def share_of_deposits(slug, from, to, interval) when slug in @ethereum do
    Eth.share_of_deposits(from, to, interval)
  end

  def share_of_deposits(contract, from, to, interval) do
    Erc20.share_of_deposits(contract, from, to, interval)
  end
end
