defmodule SanbaseWeb.Graphql.CustomTypes.LabelFqn do
  @moduledoc """
  The interval scalar type allows arbitrary interval values to be passed in and out.
  """
  use Absinthe.Schema.Notation

  scalar :interval_or_now, name: "interval_or_now" do
    description("""
    The input is either a valid `interval` type or the string `now`
    """)

    serialize(&encode/1)
    parse(&decode/1)
  end

  @spec decode(Absinthe.Blueprint.Input.String.t()) :: {:ok, term()} | :error
  @spec decode(Absinthe.Blueprint.Input.Null.t()) :: {:ok, nil}

  defp decode(%Absinthe.Blueprint.Input.String{value: label_fqn}) do
    case Sanbase.Clickhouse.Label.Validator.valid_label_fqn?(label_fqn) do
      true -> {:ok, label_fqn}
      {:error, _error} -> :error
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
