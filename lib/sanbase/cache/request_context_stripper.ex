defmodule Sanbase.Cache.RequestContextStripper do
  @moduledoc """
  Removes `Sanbase.RequestContext` from cache key inputs.

  `RequestContext` is threaded as a `:context` keyword option through
  data-layer call sites for privacy masking. Its presence must not
  change cache keys — otherwise a protected user and a non-protected
  user issuing the same query would miss each other's cache entries.

  `strip/1` walks the input tree and drops `:context` pairs whose value
  is a `%RequestContext{}`. Other structs and values pass through
  unchanged so existing cache keys stay stable across deploys.

  Hot-path note: `Sanbase.Cache.hash/1` runs on every cache key. The
  `:context` opt is only set on migrated call sites, so the common case
  is a tree without any `RequestContext` nested anywhere. `strip/1`
  short-circuits via a walk-without-allocate probe and only rebuilds
  the tree when a context is actually found.
  """

  alias Sanbase.RequestContext

  @spec strip(term()) :: term()
  def strip(data) do
    if contains?(data), do: do_strip(data), else: data
  end

  defp contains?(%RequestContext{}), do: true

  defp contains?(list) when is_list(list) do
    Enum.any?(list, &contains?/1)
  end

  defp contains?(%_{}), do: false

  defp contains?(tuple) when is_tuple(tuple) do
    contains_in_tuple?(tuple, tuple_size(tuple), 0)
  end

  defp contains?(map) when is_map(map) do
    Enum.any?(map, fn {_k, v} -> contains?(v) end)
  end

  defp contains?(_), do: false

  defp contains_in_tuple?(_tuple, size, size), do: false

  defp contains_in_tuple?(tuple, size, idx) do
    contains?(:erlang.element(idx + 1, tuple)) or
      contains_in_tuple?(tuple, size, idx + 1)
  end

  defp do_strip(%RequestContext{}), do: :_request_context

  defp do_strip(list) when is_list(list) do
    if Keyword.keyword?(list) do
      Enum.flat_map(list, fn
        {:context, %RequestContext{}} -> []
        {key, value} -> [{key, do_strip(value)}]
      end)
    else
      Enum.map(list, &do_strip/1)
    end
  end

  defp do_strip(%_{} = struct), do: struct

  defp do_strip(tuple) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.map(&do_strip/1)
    |> List.to_tuple()
  end

  defp do_strip(map) when is_map(map) do
    map
    |> Enum.flat_map(fn
      {:context, %RequestContext{}} -> []
      {k, v} -> [{k, do_strip(v)}]
    end)
    |> Map.new()
  end

  defp do_strip(other), do: other
end
