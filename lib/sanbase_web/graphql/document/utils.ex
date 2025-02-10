defmodule SanbaseWeb.Graphql.DocumentProvider.Utils do
  @moduledoc false
  @compile {:inline, cache_key_from_params: 2, variables_from_params: 1, params_variables_to_map: 1}

  @doc ~s"""
  Extract the query and variables from the params map and genenrate a cache key from them
  The query is fetched as is.
  The variables that are valid datetime types (have the `from` or `to` name and valid value)
  are converted to Elixir DateTime type before being used. This is done because
  the datetimes are rounded so all datetimes in a N minute buckets have the same cache key

  The other param types are not cast as they would be used the same way in both
  places where the cache key is calculated.
  """
  @spec cache_key_from_params(map(), map()) :: any()
  def cache_key_from_params(params, permissions) do
    query = Map.get(params, "query", "")
    variables = variables_from_params(params)

    SanbaseWeb.Graphql.Cache.cache_key({query, permissions}, variables,
      ttl: 120,
      max_ttl_offset: 90
    )
  end

  defp variables_from_params(params) do
    params
    |> params_variables_to_map()
    |> Map.new(fn
      {key, value} when is_binary(value) ->
        case DateTime.from_iso8601(value) do
          {:ok, datetime, _} -> {key, datetime}
          _ -> {key, value}
        end

      pair ->
        pair
    end)
  end

  defp params_variables_to_map(params) do
    case Map.get(params, "variables") do
      map when is_map(map) -> map
      vars when is_binary(vars) and vars != "" -> Jason.decode!(vars)
      _ -> %{}
    end
  end
end
