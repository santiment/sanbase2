defmodule SanbaseWeb.Graphql.CustomTypes.Interval do
  @moduledoc """
  The interval scalar type allows arbitrary interval values to be passed in and out.
  """
  use Absinthe.Schema.Notation

  scalar :interval, name: "interval" do
    description("""
    The `interval` scalar type represents arbitrary interval, represented as UTF-8
    character sequences.
    """)

    serialize(&encode/1)
    parse(&decode/1)
  end

  @spec decode(Absinthe.Blueprint.Input.String.t()) :: {:ok, term()} | :error
  @spec decode(Absinthe.Blueprint.Input.Null.t()) :: {:ok, nil}
  defp decode(%Absinthe.Blueprint.Input.String{value: ""}), do: {:ok, ""}

  defp decode(%Absinthe.Blueprint.Input.String{value: value}) do
    case Sanbase.DateTimeUtils.valid_compound_duration?(value) do
      true -> {:ok, value}
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
