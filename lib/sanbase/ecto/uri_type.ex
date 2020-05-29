defmodule Sanbase.Ecto.Type.URI do
  @behaviour Ecto.Type
  def type, do: :map

  def cast(uri) when is_binary(uri) do
    {:ok, URI.parse(uri)}
  end

  def cast(%URI{} = uri), do: {:ok, uri}

  def cast(_), do: :error

  def load(data) when is_map(data) do
    data =
      for {key, val} <- data do
        {String.to_existing_atom(key), val}
      end

    {:ok, struct!(URI, data)}
  end

  def dump(%URI{} = uri), do: {:ok, Map.from_struct(uri)}
  def dump(_), do: :error
end
