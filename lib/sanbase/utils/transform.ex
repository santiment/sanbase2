defmodule Sanbase.Utils.Transform do
  @doc ~s"""
  Transform the maps from the :ok tuple data so the `key` is renamed to `new_key`

  ## Examples:
      iex> Sanbase.Utils.Transform.rename_map_keys({:ok, [%{a: 1}, %{a: 2}]}, :a, :b)
      {:ok, [%{b: 1}, %{b: 2}]}

      iex> Sanbase.Utils.Transform.rename_map_keys({:ok, [%{a: 1}, %{d: 2}]}, :a, :b)
      {:ok, [%{b: 1}, %{d: 2}]}


      iex> Sanbase.Utils.Transform.rename_map_keys({:error, "bad"}, :a, :b)
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
      iex> Sanbase.Utils.Transform.rename_map_keys({:ok, [%{a: 1}, %{a: 2}]}, :a, :b)
      {:ok, [%{b: 1}, %{b: 2}]}

      iex> Sanbase.Utils.Transform.rename_map_keys({:ok, [%{a: 1}, %{d: 2}]}, :a, :b)
      {:ok, [%{b: 1}, %{d: 2}]}


      iex> Sanbase.Utils.Transform.rename_map_keys({:error, "bad"}, :a, :b)
      {:error, "bad"}
  """
  @spec rename_map_keys({:ok, list(map)}, any(), any()) :: {:ok, list(map)}
  @spec rename_map_keys({:error, any()}, any(), any()) :: {:error, any()}
  def rename_map_keys({:ok, data}, old_key, new_key) do
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

  def rename_map_keys({:error, error}, _, _) do
    {:error, error}
  end
end
