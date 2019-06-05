defmodule Sanbase.MapUtils do
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
