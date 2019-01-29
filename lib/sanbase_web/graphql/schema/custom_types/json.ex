defmodule SanbaseWeb.Graphql.CustomTypes.JSON do
  @moduledoc """
  The Json scalar type allows arbitrary JSON values to be passed in and out.
  """
  use Absinthe.Schema.Notation

  scalar :json, name: "json" do
    description("""
    The `json` scalar type represents arbitrary json string data, represented as UTF-8
    character sequences. The json type is most often used to represent a free-form
    human-readable json string.
    """)

    serialize(&encode/1)
    parse(&decode/1)
  end

  @spec decode(Absinthe.Blueprint.Input.String.t()) :: {:ok, term()} | :error
  @spec decode(Absinthe.Blueprint.Input.Null.t()) :: {:ok, nil}
  defp decode(%Absinthe.Blueprint.Input.String{value: value}) do
    case Jason.decode(value) do
      {:ok, result} -> {:ok, result}
      _ -> :error
    end
  end

  defp decode(%Absinthe.Blueprint.Input.Null{}) do
    {:ok, nil}
  end

  defp decode(_) do
    :error
  end

  defp encode(value), do: value
end
