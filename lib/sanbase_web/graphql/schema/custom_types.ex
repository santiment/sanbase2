defmodule SanbaseWeb.Graphql.CustomTypes do
  use Absinthe.Schema.Notation

  scalar :ecto_datetime, name: "EctoDateTime" do
    serialize &Ecto.DateTime.to_iso8601/1
    parse &parse_ecto_datetime/1
  end

  @spec parse_ecto_datetime(Absinthe.Blueprint.Input.String.t) :: {:ok, Ecto.DateTime.type} | :error
  @spec parse_ecto_datetime(Absinthe.Blueprint.Input.Null.t) :: {:ok, nil}
  defp parse_ecto_datetime(%Absinthe.Blueprint.Input.String{value: value}) do
    case Ecto.DateTime.cast(value) do
      {:ok, ecto_datetime} -> {:ok, ecto_datetime}
      _error -> :error
    end
  end
  defp parse_ecto_datetime(%Absinthe.Blueprint.Input.Null{}) do
    {:ok, nil}
  end
  defp parse_ecto_datetime(_) do
    :error
  end
end
