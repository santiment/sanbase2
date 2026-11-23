defmodule Sanbase.Clickhouse.JsonSafe do
  @moduledoc """
  Makes ClickHouse result rows JSON-encodable, converting each value by its column type:
  UUIDs and IPs to strings, tuples to lists, map keys to strings, other non-UTF-8
  binaries to `"base64:..."`. The driver decodes UUIDs as raw bytes and IPs as tuples,
  which Jason cannot encode.
  """

  @doc "Convert `rows` given the column type strings (e.g. `\"Nullable(UUID)\"`)."
  @spec rows([list()], [String.t()] | nil) :: [list()]
  def rows(rows, column_types) do
    types = Enum.map(column_types || [], &parse_type/1)

    Enum.map(rows, fn row ->
      if length(types) == length(row),
        do: Enum.zip_with(row, types, &value/2),
        else: Enum.map(row, &value(&1, :unknown))
    end)
  end

  defp parse_type(type) when is_binary(type) do
    Ch.Types.decode(type)
  rescue
    _ -> :unknown
  end

  defp parse_type(_type), do: :unknown

  defp value(nil, _type), do: nil
  defp value(value, {:nullable, type}), do: value(value, type)
  defp value(value, {:low_cardinality, type}), do: value(value, type)

  defp value(<<_::128>> = value, :uuid) do
    {:ok, uuid} = Ecto.UUID.load(value)
    uuid
  end

  defp value({_, _, _, _} = ip, :ipv4), do: ip |> :inet.ntoa() |> to_string()
  defp value({_, _, _, _, _, _, _, _} = ip, :ipv6), do: ip |> :inet.ntoa() |> to_string()

  defp value(value, {:fixed_string, _size}) when is_binary(value) do
    text = String.trim_trailing(value, <<0>>)
    if String.printable?(text), do: text, else: base64(value)
  end

  defp value(values, {:array, type}) when is_list(values),
    do: Enum.map(values, &value(&1, type))

  defp value(map, {:map, key_type, value_type}) when is_map(map) and not is_struct(map) do
    Map.new(map, fn {k, v} -> {map_key(value(k, key_type)), value(v, value_type)} end)
  end

  defp value(tuple, {:tuple, types})
       when is_tuple(tuple) and tuple_size(tuple) == length(types),
       do: tuple |> Tuple.to_list() |> Enum.zip_with(types, &value/2)

  defp value(tuple, _type) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.map(&value(&1, :unknown))

  defp value(list, _type) when is_list(list), do: Enum.map(list, &value(&1, :unknown))
  defp value(%{__struct__: _} = struct, _type), do: struct

  defp value(map, _type) when is_map(map),
    do: Map.new(map, fn {k, v} -> {map_key(value(k, :unknown)), value(v, :unknown)} end)

  defp value(value, _type) when is_binary(value),
    do: if(String.valid?(value), do: value, else: base64(value))

  defp value(value, _type), do: value

  defp map_key(key) when is_binary(key), do: key
  defp map_key(key), do: Jason.encode!(key)

  defp base64(value), do: "base64:" <> Base.encode64(value)
end
