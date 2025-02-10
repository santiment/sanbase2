defmodule SanbaseWeb.Graphql.CustomTypes.IntervalOrNow do
  @moduledoc """
  The interval scalar type allows arbitrary interval values to be passed in and out.
  """
  use Absinthe.Schema.Notation

  alias Absinthe.Blueprint.Input.Null

  scalar :interval_or_now, name: "interval_or_now" do
    description("""
    The input is either a valid `interval` type or the string `now`
    """)

    serialize(&encode/1)
    parse(&decode/1)
  end

  @spec decode(Absinthe.Blueprint.Input.String.t()) :: {:ok, term()} | :error
  @spec decode(Null.t()) :: {:ok, nil}
  defp decode(%Absinthe.Blueprint.Input.String{value: "now"}), do: {:ok, "now"}

  defp decode(%Absinthe.Blueprint.Input.String{value: value}) do
    if Sanbase.DateTimeUtils.valid_compound_duration?(value) do
      {:ok, value}
    else
      :error
    end
  end

  defp decode(%Null{}) do
    {:ok, nil}
  end

  defp decode(_) do
    :error
  end

  defp encode(value), do: value
end
