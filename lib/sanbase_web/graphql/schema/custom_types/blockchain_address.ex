defmodule SanbaseWeb.Graphql.CustomTypes.BlockchainAddress do
  @moduledoc """
  The interval scalar type allows arbitrary interval values to be passed in and out.
  """
  use Absinthe.Schema.Notation

  alias Absinthe.Blueprint.Input.Null

  # Types must have a unique name. `:blockchain_address` is already taken
  scalar :binary_blockchain_address, name: "binary_blockchain_address" do
    description("""
    The `blockchain_address` scalar type is the binary representation of blockchain
    addresses, represented as UTF-8 character sequences (string).
    When decoding, some addresses will be lowercased to avoid casing issues (ethereum).
    The addresses are encoded as they are, without changes.
    """)

    serialize(&encode/1)
    parse(&decode/1)
  end

  @spec decode(Absinthe.Blueprint.Input.String.t()) :: {:ok, term()} | :error
  @spec decode(Null.t()) :: {:ok, nil}
  defp decode(%Absinthe.Blueprint.Input.String{value: ""}), do: {:ok, ""}

  defp decode(%Absinthe.Blueprint.Input.String{value: value}) do
    value = Sanbase.BlockchainAddress.to_internal_format(value)
    {:ok, value}
  end

  defp decode(%Null{}) do
    {:ok, nil}
  end

  defp decode(_) do
    :error
  end

  defp encode(value), do: value
end
