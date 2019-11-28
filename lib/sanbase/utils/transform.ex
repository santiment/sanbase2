defmodule Sanbase.Utils.Transform do
  @doc ~s"""
  Transform the maps from the :ok tuple data so the `key` is renamed to `new_key`

  ## Examples:
      iex> Sanbase.Utils.Transform.rename_map_keys({:ok, [%{a: 1}, %{a: 2}]}, old_key: :a, new_key: :b)
      {:ok, [%{b: 1}, %{b: 2}]}

      iex> Sanbase.Utils.Transform.rename_map_keys({:ok, [%{a: 1}, %{d: 2}]}, old_key: :a, new_key: :b)
      {:ok, [%{b: 1}, %{d: 2}]}


      iex> Sanbase.Utils.Transform.rename_map_keys({:error, "bad"}, old_key: :a, new_key: :b)
      {:error, "bad"}
  """
  @spec duplicate_map_keys({:ok, list(map)}, any(), any()) :: {:ok, list(map)}
  @spec duplicate_map_keys({:error, any()}, any(), any()) :: {:error, any()}
  def duplicate_map_keys({:ok, data}, key, new_key) do
    result =
      data
      |> Enum.map(fn
        %{^key => value} = elem -> elem |> Map.put(new_key, value)
        elem -> elem
      end)

    {:ok, result}
  end

  def duplicate_map_keys({:error, error}, _, _) do
    {:error, error}
  end

  @doc ~s"""
  Transform the maps from the :ok tuple data so the `key` duplicated with a key
  named `new_key`

  ## Examples:
      iex> Sanbase.Utils.Transform.rename_map_keys({:ok, [%{a: 1}, %{a: 2}]}, old_key: :a, new_key: :b)
      {:ok, [%{b: 1}, %{b: 2}]}

      iex> Sanbase.Utils.Transform.rename_map_keys({:ok, [%{a: 1}, %{d: 2}]}, old_key: :a, new_key: :b)
      {:ok, [%{b: 1}, %{d: 2}]}


      iex> Sanbase.Utils.Transform.rename_map_keys({:error, "bad"}, old_key: :a, new_key: :b)
      {:error, "bad"}
  """
  @spec rename_map_keys({:ok, list(map)}, keyword(atom())) :: {:ok, list(map)}
  @spec rename_map_keys({:error, any()}, keyword(atom())) :: {:error, any()}
  def rename_map_keys({:ok, data}, opts) do
    old_key = Keyword.get(opts, :old_key)
    new_key = Keyword.get(opts, :new_key)

    result =
      data
      |> Enum.map(fn
        %{^old_key => value} = elem ->
          elem |> Map.delete(old_key) |> Map.put(new_key, value)

        elem ->
          elem
      end)

    {:ok, result}
  end

  def rename_map_keys({:error, error}, _) do
    {:error, error}
  end

  def rename_map_keys!(map, old_keys: old_keys, new_keys: new_keys) do
    old_new_keys_map = Enum.zip(old_keys, new_keys) |> Enum.into(%{})

    map
    |> Enum.map(fn {k, v} -> {old_new_keys_map[k] || k, v} end)
    |> Enum.into(%{})
  end

  def unpack_value({:ok, [value]}), do: {:ok, value}
  def unpack_value({:error, error}), do: {:error, error}
end
