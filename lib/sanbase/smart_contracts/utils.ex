defmodule Sanbase.SmartContracts.Utils do
  @type address :: String.t()
  @type contract_function :: String.t() | %ABI.FunctionSelector{}

  @desc ~s"""
  Example usage:
  If we have the abi specification obtained by:
  ```
  File.read!("some_abi.json")
  |> Jason.decode!
  |> ABI.parse_specification
  |> Enum.find(&(&1.function == "walletProposals"))
  ```

  ```
  function_selector = %ABI.FunctionSelector{
      function: "walletProposals",
      input_names: ["startRequestId", "pageSize"],
      inputs_indexed: nil,
      method_id: <<50, 0, 127, 55>>,
      returns: [
        array: {:tuple,
        [
          {:uint, 256},
          :address,
          {:uint, 256},
          {:uint, 8},
          :bool,
          {:uint, 256},
          {:uint, 256},
          {:uint, 256},
          {:uint, 256},
          {:uint, 256},
          {:uint, 256}
        ]}
      ],
      type: :function,
      types: [uint: 256, uint: 256]
  }
  ```

  We can execute a contract function/event that way:
  ```
  call_contract(
    contract_address_string
    function_selector
    [0, 10], #input args of the corresponding `function_selector.input_names` with types `function_selector.types`
    function_selector.returns
  )
  ```
  """
  @spec call_contract(address, contract_function, list(), list()) :: any()
  def call_contract(contract, contract_function, args, return_types) do
    # https://docs.soliditylang.org/en/latest/abi-spec.html#function-selector-and-argument-encoding
    function_signature = ABI.encode(contract_function, args) |> Base.encode16(case: :lower)

    {:ok, hex_encoded_binary_response} =
      Ethereumex.HttpClient.eth_call(%{
        data: "0x" <> function_signature,
        to: contract
      })

    hex_encoded_binary_response
    # Strip `0x` prefix
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
