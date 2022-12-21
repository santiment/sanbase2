defmodule Sanbase.SmartContracts.Utils do
  require Logger

  @type address :: String.t()
  @type contract_function :: String.t() | %ABI.FunctionSelector{}

  @doc ~s"""
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

    Logger.info(
      "[EthNode] Eth call contract with function #{get_function_name(contract_function)}."
    )

    function_signature =
      ABI.encode(contract_function, args)
      |> Base.encode16(case: :lower)

    with {:ok, hex_encoded_binary_response} <-
           Ethereumex.HttpClient.eth_call(%{data: "0x" <> function_signature, to: contract}) do
      hex_encoded_binary_response
      # Strip `0x` prefix
      |> String.slice(2..-1)
      |> Base.decode16!(case: :lower)
      |> case do
        "" -> :error
        response -> ABI.TypeDecoder.decode_raw(response, return_types)
      end
    end
  end

  def call_contract_batch(contract, contract_function, args_lists, return_types, opts \\ []) do
    transform_args = Keyword.get(opts, :transform_args_list_fun, fn x -> x end)

    Logger.info(
      "[EthNode] Eth call contract batch with function #{get_function_name(contract_function)}."
    )

    requests =
      Enum.map(args_lists, fn args ->
        function_signature = ABI.encode(contract_function, args) |> Base.encode16(case: :lower)
        eth_call_args = [%{data: "0x" <> function_signature, to: contract}] |> transform_args.()

        {:eth_call, eth_call_args}
      end)

    with {:ok, result} <- Ethereumex.HttpClient.batch_request(requests) do
      Enum.map(result, fn {:ok, hex_encoded_binary_response} ->
        hex_encoded_binary_response
        # Strip `0x` prefix
        |> String.slice(2..-1)
        |> Base.decode16!(case: :lower)
        |> ABI.TypeDecoder.decode_raw(return_types)
      end)
    end
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

  def address_strip_zeros(address) do
    address =
      address
      |> String.slice(2..-1)
      |> Integer.parse(16)
      |> elem(0)
      |> Integer.to_string(16)
      |> String.downcase()

    "0x" <> address
  end

  defp get_function_name(function) when is_binary(function), do: function
  defp get_function_name(%{function: function}), do: function
  defp get_function_name(function), do: inspect(function) <> "Unexpected"
end
