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

  def maybe_unwrap_ok_value({:ok, [value]}), do: {:ok, value}
  def maybe_unwrap_ok_value({:ok, []}), do: {:ok, nil}
  def maybe_unwrap_ok_value({:error, error}), do: {:error, error}

  def maybe_apply_function({:ok, list}, fun) when is_list(list) and is_function(fun, 1),
    do: {:ok, fun.(list)}

  def maybe_apply_function({:error, error}), do: {:error, error}

  @doc ~s"""
  Sums the values of all keys with the same datetime

  ## Examples:
      iex> Sanbase.Utils.Transform.sum_by_datetime([%{datetime: ~U[2019-01-01 00:00:00Z], val: 2}, %{datetime: ~U[2019-01-01 00:00:00Z], val: 3}, %{datetime: ~U[2019-01-02 00:00:00Z], val: 2}], :val)
      [%{datetime: ~U[2019-01-01 00:00:00Z], val: 5}, %{datetime: ~U[2019-01-02 00:00:00Z], val: 2}]

      iex> Sanbase.Utils.Transform.sum_by_datetime([], :key)
      []
  """
  @spec sum_by_datetime(list(map), atom()) :: list(map)
  def sum_by_datetime(data, key) do
    data
    |> Enum.group_by(& &1[:datetime], & &1[key])
    |> Enum.map(fn {datetime, list} ->
      value =
        case list do
          [] -> 0
          [_ | _] = list -> Enum.sum(list)
        end

      %{:datetime => datetime, key => value}
    end)
    |> Enum.sort_by(&DateTime.to_unix(&1[:datetime]))
  end

  def maybe_transform_from_address("0x0000000000000000000000000000000000000000"), do: "mint"
  def maybe_transform_from_address(address), do: address
  def maybe_transform_to_address("0x0000000000000000000000000000000000000000"), do: "burn"
  def maybe_transform_to_address(address), do: address
end
