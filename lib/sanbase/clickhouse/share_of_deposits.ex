defmodule Sanbase.Clickhouse.ShareOfDeposits do
  @moduledoc ~s"""
  Dispatch the calculations of share of deposits to the correct module
  """
  alias Sanbase.Clickhouse.Erc20ShareOfDeposits, as: Erc20
  alias Sanbase.Clickhouse.EthShareOfDeposits, as: Eth

  @ethereum ["ethereum", "ETH"]

  def share_of_deposits(eth, from, to, interval) when eth in @ethereum do
    Eth.share_of_deposits(from, to, interval)
  end

  def share_of_deposits(contract, from, to, interval) do
    Erc20.share_of_deposits(contract, from, to, interval)
  end
end
