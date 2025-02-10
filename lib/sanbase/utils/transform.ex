defmodule Sanbase.Utils.Transform do
  @moduledoc false
  def to_bang(result) do
    case result do
      {:ok, result} -> result
      {:error, error} -> raise error
    end
  end

  @doc ~s"""
  Combine all the MapSets from the mapsets_list either by
  taking their intersection or their union. The decision is
  made based on the `:combinator` field in the opts

  ## Examples:
      iex> Sanbase.Utils.Transform.combine_mapsets([MapSet.new([1,2,3]), MapSet.new([2,3,4,5])], combinator: "or")
      MapSet.new([1,2,3,4,5])

      iex> Sanbase.Utils.Transform.combine_mapsets([MapSet.new([1,2,3]), MapSet.new([2,3,4,5])], combinator: "and")
      MapSet.new([2,3])

  """
  def combine_mapsets(mapsets_list, opts) do
    case Keyword.fetch!(opts, :combinator) do
      c when c in ["or", :or] ->
        Enum.reduce(mapsets_list, &MapSet.union(&1, &2))

      c when c in ["and", :and] ->
        Enum.reduce(mapsets_list, &MapSet.intersection(&1, &2))
    end
  end

  @doc ~s"""
  Simply wrap anything in an :ok tuple
  """
  @spec wrap_ok(any()) :: {:ok, any()}
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
      Enum.map(data, fn
        %{^old_key => value} = elem -> Map.put(elem, new_key, value)
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
      Enum.map(data, fn
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
    old_new_keys_map = old_keys |> Enum.zip(new_keys) |> Map.new()

    Map.new(map, fn {k, v} -> {old_new_keys_map[k] || k, v} end)
  end

  @doc ~s"""
  Transform an :ok tuple containing a list of a single value to an :ok tuple
  that unwraps the value in the list. Handles the cases of errors
  or empty list.

  ## Examples:
    iex> Sanbase.Utils.Transform.maybe_unwrap_ok_value({:ok, [5]})
    {:ok, 5}

    iex> Sanbase.Utils.Transform.maybe_unwrap_ok_value({:error, "error"})
    {:error, "error"}


    iex> Sanbase.Utils.Transform.maybe_unwrap_ok_value({:ok, 5})
    ** (RuntimeError) Unsupported format given to maybe_unwrap_ok_value/1: 5
  """
  @spec maybe_unwrap_ok_value({:ok, any}) :: {:ok, any()} | {:error, String.t()}
  @spec maybe_unwrap_ok_value({:error, any()}) :: {:error, any()}
  def maybe_unwrap_ok_value({:ok, [value]}), do: {:ok, value}
  def maybe_unwrap_ok_value({:ok, []}), do: {:ok, nil}

  def maybe_unwrap_ok_value({:ok, value}),
    do: raise("Unsupported format given to maybe_unwrap_ok_value/1: #{inspect(value)}")

  def maybe_unwrap_ok_value({:error, error}), do: {:error, error}

  def maybe_extract_value_from_tuple({:ok, value}), do: value
  def maybe_extract_value_from_tuple({:error, error}), do: {:error, error}

  def maybe_apply_function({:ok, list}, fun) when is_function(fun, 1), do: {:ok, fun.(list)}

  def maybe_apply_function({:error, error}, _), do: {:error, error}

  def maybe_transform_datetime_data_tuple_to_map(data) do
    maybe_apply_function(data, fn list ->
      Enum.map(list, fn {datetime, data} -> %{datetime: datetime, data: data} end)
    end)
  end

  @doc ~s"""
  If the data is an ok tuple, sort it using the provided key and direction.
  The function is specialized for datetime, so it uses the proper way to compare
  datetimes.


  ## Examples:
    iex> Sanbase.Utils.Transform.maybe_sort(
    ...>   {:ok, [%{datetime: ~U[2022-01-01 00:00:00Z]},%{datetime: ~U[2022-01-01 02:00:00Z]}]},
    ...>   :datetime,
    ...>   :desc
    ...> )
    {:ok, [%{datetime: ~U[2022-01-01 02:00:00Z]}, %{datetime: ~U[2022-01-01 00:00:00Z]}]}

    iex> Sanbase.Utils.Transform.maybe_sort(
    ...>   {:ok, [%{a: 1, value: 5}, %{a: 100, value: 4}, %{a: -1, value: 6}]},
    ...>   :value,
    ...>   :asc
    ...> )
    {:ok, [%{a: 100, value: 4}, %{a: 1, value: 5}, %{a: -1, value: 6}]}
  """
  def maybe_sort(data, :datetime, direction) when direction in [:asc, :desc] do
    maybe_apply_function(data, fn list ->
      Enum.sort_by(list, & &1.datetime, {direction, DateTime})
    end)
  end

  def maybe_sort(data, key, direction) when direction in [:asc, :desc] do
    maybe_apply_function(data, fn list ->
      Enum.sort_by(list, & &1[key], direction)
    end)
  end

  @doc ~s"""
  Sums the values of all keys with the same datetime

  ## Examples:
      iex> Sanbase.Utils.Transform.sum_by_datetime([
      ...>  %{datetime: ~U[2019-01-01 00:00:00Z], val: 2},
      ...>  %{datetime: ~U[2019-01-01 00:00:00Z], val: 3},
      ...>  %{datetime: ~U[2019-01-02 00:00:00Z], val: 2}],
      ...>  :val
      ...> )
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

  @doc ~s"""
  Combine the values of `key` in list1 and list2 by using `func`. The result with
  the same `datetime` values are chosen to be merged.

  ## Example
    iex> Sanbase.Utils.Transform.merge_by_datetime([%{a: 3.5, datetime: ~U[2020-01-01 00:00:00Z]}, %{a: 2, datetime: ~U[2020-01-02 00:00:00Z]}], [%{a: 10, datetime: ~U[2020-01-01 00:00:00Z]}, %{a: 6, datetime: ~U[2020-01-02 00:00:00Z]}], &Kernel.*/2, :a)
    [%{a: 35.0, datetime: ~U[2020-01-01 00:00:00Z]}, %{a: 12, datetime: ~U[2020-01-02 00:00:00Z]}]
  """
  @spec merge_by_datetime(list(), list(), fun(), any()) :: list()
  def merge_by_datetime(list1, list2, func, key) do
    map = Map.new(list2, fn %{datetime: dt} = item2 -> {dt, item2[key]} end)

    list1
    |> Enum.map(fn %{datetime: datetime} = item1 ->
      value2 = Map.get(map, datetime, 0)
      new_value = func.(item1[key], value2)

      %{key => new_value, datetime: datetime}
    end)
    |> Enum.reject(&(&1[key] == 0))
  end

  @doc ~s"""
  Transform some addresses to a name representation
  """
  @spec maybe_transform_from_address(String.t()) :: String.t()
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

  @doc ~s"""
  Get a list of maps that must have a key named `key` that may be not
  computed. These values are recognized by the `has_changed` key that can
  be either 0 or 1.
  In case the value of a key is missing it is filled with the last known
  value by its order in the list

  ## Example
    iex> Sanbase.Utils.Transform.maybe_fill_gaps_last_seen({:ok, [%{a: 1, has_changed: 1}, %{a: nil, has_changed: 0}, %{a: 5, has_changed: 1}]}, :a)
    {:ok, [%{a: 1}, %{a: 1}, %{a: 5}]}

    iex> Sanbase.Utils.Transform.maybe_fill_gaps_last_seen({:ok, [%{a: nil, has_changed: 0}, %{a: nil, has_changed: 0}, %{a: 5, has_changed: 1}]}, :a)
    {:ok, [%{a: 0}, %{a: 0}, %{a: 5}]}

    iex> Sanbase.Utils.Transform.maybe_fill_gaps_last_seen({:ok, [%{a: 1, has_changed: 1}, %{a: 2, has_changed: 1}, %{a: 5, has_changed: 1}]}, :a)
    {:ok, [%{a: 1}, %{a: 2}, %{a: 5}]}

    iex> Sanbase.Utils.Transform.maybe_fill_gaps_last_seen({:ok, [%{a: 1, has_changed: 1}, %{a: nil, has_changed: 0}, %{a: nil, has_changed: 0}]}, :a)
    {:ok, [%{a: 1}, %{a: 1}, %{a: 1}]}
  """
  def maybe_fill_gaps_last_seen(result_tuple, key, unknown_previous_value \\ 0)

  def maybe_fill_gaps_last_seen({:ok, values}, key, unknown_previous_value) do
    result =
      values
      |> Enum.reduce({[], unknown_previous_value}, fn
        %{has_changed: 0} = elem, {acc, last_seen} ->
          elem = elem |> Map.put(key, last_seen) |> Map.delete(:has_changed)
          {[elem | acc], last_seen}

        %{has_changed: 1} = elem, {acc, _last_seen} ->
          elem = Map.delete(elem, :has_changed)
          {[elem | acc], elem[key]}
      end)
      |> elem(0)
      |> Enum.reverse()

    {:ok, result}
  end

  def maybe_fill_gaps_last_seen({:error, error}, _key, _unknown_previous_value), do: {:error, error}

  @spec opts_to_limit_offset(page: non_neg_integer(), page_size: pos_integer()) ::
          {pos_integer(), non_neg_integer()}
  def opts_to_limit_offset(opts) do
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 10)
    offset = (page - 1) * page_size

    {page_size, offset}
  end
end
