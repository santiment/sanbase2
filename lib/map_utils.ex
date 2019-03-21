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
end
