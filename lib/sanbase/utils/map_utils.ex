defmodule Sanbase.MapUtils do
  def rename_key(map, old_key, new_key) do
    case Map.has_key?(map, old_key) do
      true ->
        value = Map.get(map, old_key)
        map |> Map.delete(old_key) |> Map.put(new_key, value)

      false ->
        {:error, "The key '#{old_key}' does not exist in the map"}
    end
  end

  def replace_lazy(map, key, value_fun) do
    case Map.has_key?(map, key) do
      true -> Map.put(map, key, value_fun.())
      false -> map
    end
  end

  @doc ~s"""
  Return a subset of `left` map that has only the keys that are also present in `right`.

  #### Examples:
    iex> Sanbase.MapUtils.drop_diff_keys(%{}, %{})
    %{}

    iex> Sanbase.MapUtils.drop_diff_keys(%{a: 1}, %{a: 1})
    %{a: 1}

    iex> Sanbase.MapUtils.drop_diff_keys(%{a: 1, b: 2}, %{a: 1})
    %{a: 1}

    iex> Sanbase.MapUtils.drop_diff_keys(%{a: 1}, %{a: "ASDASDASDA"})
    %{a: 1}

    iex> Sanbase.MapUtils.drop_diff_keys(%{a: 1, d: 555, e: "string"}, %{b: 2, c: 3, f: 19})
    %{}
  """
  def drop_diff_keys(left, right) do
    Map.drop(left, Map.keys(left) -- Map.keys(right))
  end

  @doc ~s"""
  Find where a given name-value pair is located in a deeply nested list-map data
  structures.

  #### Examples:
    iex> %{a: %{b: %{"name" => "ivan"}}} |> Sanbase.MapUtils.find_pair_path("name", "ivan")
    [[:a, :b, "name"]]

    iex> %{a: %{b: [%{"name" => "ivan"}]}} |> Sanbase.MapUtils.find_pair_path("name", "ivan")
    [[:a, :b, {:at, 0}, "name"]]

    iex> %{a: [%{b: [%{"name" => "ivan"}]}]} |> Sanbase.MapUtils.find_pair_path("name", "ivan")
    [[:a, {:at, 0}, :b, {:at, 0}, "name"]]

    iex>%{
    ...> "foo" => %{"last" => [%{b: [%{"name" => "ivan"}]}]},
    ...> a: %{"some" => %{a: 2, c: 12}, "key" => [1, 2, 3, 4, 5, 6]}
    ...> } |> Sanbase.MapUtils.find_pair_path("name", "ivan")
    [["foo", "last", {:at, 0}, :b, {:at, 0}, "name"]]

    iex> %{a: %{b: [%{"name" => ""}]}} |> Sanbase.MapUtils.find_pair_path("name", "not_existing")
    []

    iex> %{a: %{b: [%{"name" => ""}]}} |> Sanbase.MapUtils.find_pair_path("not_existing", "ivan")
    []
  """
  def find_pair_path(map, key, value) when is_map(map) do
    do_find_pair_path(map, key, value, [])
    |> Enum.map(&(&1 |> List.flatten() |> Enum.reverse()))
    |> Enum.reject(&(&1 == nil || &1 == []))
  end

  @doc ~s"""
  Atomize the string keys of a map or list of maps.

  #### Examples:
    iex> %{"a" => %{"b" => %{"name" => "ivan"}}} |> Sanbase.MapUtils.atomize_keys()
    %{a: %{b: %{name: "ivan"}}}

    iex> [%{"a" => 1}, %{"b" => [%{"c" => %{"d" => 12}}]}] |> Sanbase.MapUtils.atomize_keys()
    [%{a: 1}, %{b: [%{c: %{d: 12}}]}]

    iex> %{} |> Sanbase.MapUtils.atomize_keys()
    %{}

    iex> [%{}, %{}] |> Sanbase.MapUtils.atomize_keys()
    [%{}, %{}]


    iex> %{already: %{atom: :atom}} |> Sanbase.MapUtils.atomize_keys()
    %{already: %{atom: :atom}}
  """
  def atomize_keys(list) when is_list(list) do
    Enum.map(list, fn elem -> atomize_keys(elem) end)
  end

  def atomize_keys(map) when is_map(map) and not is_struct(map) do
    Enum.reduce(map, %{}, fn {key, val}, acc ->
      Map.put(acc, atomize(key), atomize_keys(val))
    end)
  end

  def atomize_keys(data), do: data

  @doc ~s"""

  Merge two maps deeply. If a key exists in both maps and the value is a map, the
  function will merge the two maps recursively. If the value is not a map, the
  value from the second map will be used.

  #### Examples:

    iex> map1 = %{
    ...>   a: 1,
    ...>   b: %{
    ...>     c: 2,
    ...>     d: %{
    ...>       e: 3
    ...>     }
    ...>   }
    ...> }
    iex> map2 = %{
    ...>   a: 2,
    ...>   b: %{
    ...>     c: 3,
    ...>     d: %{
    ...>       e: 4
    ...>     }
    ...>   }
    ...> }
    iex> Sanbase.MapUtils.merge_deep(map1, map2)
    %{
      a: 2,
      b: %{
        c: 3,
        d: %{
          e: 4
        }
      }
    }

    iex> map1 = %{
    ...>   a: 1,
    ...>   b: %{
    ...>     c: 2,
    ...>     d: %{
    ...>       e: 3
    ...>     }
    ...>   }
    ...> }
    iex> map2 = %{
    ...>   a: 2,
    ...>   b: %{
    ...>     c: 3,
    ...>     d: %{
    ...>       e: 4,
    ...>       f: 5
    ...>     }
    ...>   }
    ...> }
    iex> Sanbase.MapUtils.merge_deep(map1, map2)
    %{
      a: 2,
      b: %{
        c: 3,
        d: %{
          e: 4,
          f: 5
        }
      }
    }
  """
  def merge_deep(map1, map2) do
    map2
    |> Enum.reduce(map1, fn {key, val}, acc ->
      if Map.has_key?(acc, key) and is_map(val) and is_map(Map.get(acc, key)) do
        Map.put(acc, key, merge_deep(Map.get(acc, key), val))
      else
        Map.put(acc, key, val)
      end
    end)
  end

  # Private functions

  @compile {:inline, atomize: 1}
  case Mix.env() == :test do
    true ->
      defp atomize(value) when is_atom(value) or is_binary(value) do
        # In :test env we can safely ignore this error
        # credo:disable-for-next-line
        value |> Inflex.underscore() |> String.to_atom()
      end

    false ->
      defp atomize(value) when is_atom(value) or is_binary(value) do
        value |> Inflex.underscore() |> String.to_existing_atom()
      end
  end

  defp do_find_pair_path(map, key, value, path) when is_map(map) do
    keys = Map.keys(map)

    if key in keys and Map.get(map, key) == value do
      [key | path]
    else
      Enum.map(keys, fn subkey ->
        Map.get(map, subkey)
        |> do_find_pair_path(key, value, [subkey | path])
      end)
    end
  end

  defp do_find_pair_path(list, key, value, path) when is_list(list) do
    Enum.with_index(list)
    |> Enum.map(fn {elem, index} ->
      do_find_pair_path(elem, key, value, [{:at, index} | path])
    end)
  end

  defp do_find_pair_path(_, _, _, _), do: []
end
