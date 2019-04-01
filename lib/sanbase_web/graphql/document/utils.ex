defmodule SanbaseWeb.Graphql.DocumentProvider.Utils do
  @compile :inline_list_funcs
  @compile {:inline, cache_key_from_params: 2}

  @datetime_field_names ["from", "to"]

  @doc ~s"""
  Extract the query and variables from the params map and genenrate a cache key from them
  The query is fetched as is.
  The variables that are valid datetime types (have the `from` or `to` name and valid vaule)
  are concerted to Elixir DateTime type before being used.

  The other param types are not cast as they would be used the same way in both
  places where the cache key is calculated.
  """
  @spec cache_key_from_params(map(), map()) :: any()
  def cache_key_from_params(params, permissions) do
    query = Map.get(params, "query", "")

    variables =
      case Map.get(params, "variables") do
        map when is_map(map) -> map
        vars when is_binary(vars) and vars != "" -> vars |> Jason.decode!()
        _ -> %{}
      end
      |> Enum.map(fn
        {key, value} when key in @datetime_field_names and is_binary(value) ->
          case DateTime.from_iso8601(value) do
            {:ok, datetime, _} -> {key, datetime}
            _ -> {key, value}
          end

        pair ->
          pair
      end)
      |> Map.new()

    # Cache for between 30 seconds and 90 seconds
    SanbaseWeb.Graphql.Cache.cache_key({query, permissions}, variables,
      ttl: 30,
      max_ttl_offset: 60
    )
  end
end
