defmodule Sanbase.SmartContracts.Utils do
  def format_number(number, decimals) do
    number / Sanbase.Math.ipow(10, decimals)
  end

  def format_address(address) do
    {:ok, address} =
      address
      |> String.slice(2..-1)
      |> Base.decode16(case: :mixed)

    address
  end
end
