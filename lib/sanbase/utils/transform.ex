defmodule Sanbase.Utils.Transform do
  def wrap_ok(data), do: {:ok, data}

  @doc ~s"""
  Transform the maps from the :ok tuple data so the `key` is duplicated under the
  `new_key` name, preserving the original value.

  ## Examples:
      iex> Sanbase.Utils.Transform.duplicate_map_keys({:ok, [%{a: 1}, %{a: 2}]}, old_key: :a, new_key: :b)
      {:ok, [%{a: 1, b: 1}, %{a: 2, b: 2}]}

      iex> Sanbase.Utils.Transform.duplicate_map_keys({:ok, [%{a: 1}, %{d: 2}]}, old_key: :a, new_key: :b)
      {:ok, [%{a: 1, b: 1}, %{d: 2}]}


      iex> Sanbase.Utils.Transform.duplicate_map_keys({:error, "bad"}, old_key: :a, new_key: :b)
      {:error, "bad"}
  """
  @spec duplicate_map_keys({:ok, list(map)}, keyword(atom)) :: {:ok, list(map)}
  @spec duplicate_map_keys({:error, any()}, keyword(atom)) :: {:error, any()}
  def duplicate_map_keys({:ok, data}, opts) do
    old_key = Keyword.fetch!(opts, :old_key)
    new_key = Keyword.fetch!(opts, :new_key)

    result =
      data
      |> Enum.map(fn
        %{^old_key => value} = elem -> elem |> Map.put(new_key, value)
        elem -> elem
      end)

    {:ok, result}
  end

  def duplicate_map_keys({:error, error}, _opts) do
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
    old_key = Keyword.fetch!(opts, :old_key)
    new_key = Keyword.fetch!(opts, :new_key)

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

  def maybe_apply_function({:ok, list}, fun) when is_function(fun, 1),
    do: {:ok, fun.(list)}

  def maybe_apply_function({:error, error}, _), do: {:error, error}

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

  def merge_by_datetime(list1, list2, func, field) do
    map = list2 |> Enum.into(%{}, fn %{datetime: dt} = item2 -> {dt, item2[field]} end)

    list1
    |> Enum.map(fn %{datetime: datetime} = item1 ->
      value2 = Map.get(map, datetime, 0)
      new_value = func.(item1[field], value2)

      %{datetime: datetime, value: new_value}
    end)
    |> Enum.reject(&(&1.value == 0))
  end

  def maybe_transform_from_address("0x0000000000000000000000000000000000000000"), do: "mint"
  def maybe_transform_from_address(address), do: address
  def maybe_transform_to_address("0x0000000000000000000000000000000000000000"), do: "burn"
  def maybe_transform_to_address(address), do: address

  @doc ~s"""
  Remove the `separator` inside the value of the key `key` in the map `map`

  ## Examples:
      iex> Sanbase.Utils.Transform.remove_separator(%{a: "100,000"}, :a, ",")
      %{a: "100000"}

      iex> Sanbase.Utils.Transform.remove_separator(%{a: "100,000", b: "5,000"}, :a, ",")
      %{a: "100000", b: "5,000"}


      iex> Sanbase.Utils.Transform.remove_separator(%{a: "100,000"}, :c, ",")
      %{a: "100,000"}
  """
  def remove_separator(map, key, separator) do
    case Map.fetch(map, key) do
      :error -> map
      {:ok, value} -> Map.put(map, key, String.replace(value, separator, ""))
    end
  end

  def maybe_fill_gaps_last_seen({:ok, values}, key) do
    result =
      values
      |> Enum.reduce({[], 0}, fn
        %{has_changed: 0} = elem, {acc, last_seen} ->
          elem = Map.put(elem, key, last_seen) |> Map.delete(:has_changed)
          {[elem | acc], last_seen}

        %{has_changed: 1} = elem, {acc, _last_seen} ->
          elem = Map.delete(elem, :has_changed)
          {[elem | acc], elem[key]}
      end)
      |> elem(0)
      |> Enum.reverse()

    {:ok, result}
  end

  def maybe_fill_gaps_last_seen({:error, error}, _key), do: {:error, error}

  @spec opts_to_limit_offset(page: non_neg_integer(), page_size: pos_integer()) ::
          {pos_integer(), non_neg_integer()}
  def opts_to_limit_offset(opts) do
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 10)
    offset = (page - 1) * page_size

    {page_size, offset}
  end
end
