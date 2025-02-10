defmodule SanbaseWeb.Graphql.CustomTypes.Date do
  @moduledoc false
  use Absinthe.Schema.Notation

  alias Absinthe.Blueprint.Input.Null

  scalar :date do
    description("""
    The `Date` scalar type represents a date. The Date appears in a JSON
    response as an ISO8601 formatted string, without a time component.
    """)

    serialize(&Date.to_iso8601/1)
    parse(&parse_date/1)
  end

  @spec parse_date(Absinthe.Blueprint.Input.String.t()) :: {:ok, Date.t()} | :error
  @spec parse_date(Null.t()) :: {:ok, nil}
  defp parse_date(%Absinthe.Blueprint.Input.String{value: value}) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      _error -> :error
    end
  end

  defp parse_date(%Null{}) do
    {:ok, nil}
  end

  defp parse_date(_) do
    :error
  end
end
