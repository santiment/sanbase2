defmodule Sanbase.SantimentContract do
  @moduledoc ~s"""
  Module containing deta regarding Santiment's contract
  """
  def decimals, do: 18
  def decimals_expanded, do: 1_000_000_000_000_000_000
  def contract, do: "0x7c5a0ce9267ed19b22f8cae653f198e3e8daf098"
  def contract_checksumed, do: "0x7C5A0CE9267ED19B22F8cae653F198e3E8daf098"
  def total_supply, do: 83_337_000
  def ticker, do: "SAN"
end
