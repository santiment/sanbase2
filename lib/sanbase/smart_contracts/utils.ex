defmodule Sanbase.SmartContracts.Utils do
  @type address :: String.t()

  @spec call_contract(address, String.t(), list(), list()) :: any()
  def call_contract(contract, call, args, return_types) do
    abi = ABI.encode(call, args) |> Base.encode16(case: :lower)

    {:ok, res_enc} =
      Ethereumex.HttpClient.eth_call(%{
        data: "0x" <> abi,
        to: contract
      })

    res_enc
    |> String.slice(2..-1)
    |> Base.decode16!(case: :lower)
    |> ABI.TypeDecoder.decode_raw(return_types)
  end

  def format_number(number, decimals \\ 18)

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

  def encode_address(address) do
    "0x" <> Base.encode16(address, case: :lower)
  end
end
