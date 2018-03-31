defmodule SanbaseWeb.Graphql.Helpers.Cache do
  @ttl :timer.minutes(5)
  @cache_name :graphql_cache

  def from(captured_mfa) when is_function(captured_mfa) do
    fun_name =
      captured_mfa
      |> :erlang.fun_info()
      |> Keyword.get(:name)

    captured_mfa
    |> resolver(fun_name)
  end

  def from(fun, fun_name) when is_function(fun) do
    fun
    |> resolver(fun_name)
  end

  def func(cached_func, name, args \\ %{}) do
    fn ->
      {_, value} =
        Cachex.fetch(@cache_name, cache_key(name, args, %{}), fn ->
          {:commit, cached_func.()}
        end)

      value
    end
  end

  def clear_all() do
    Cachex.clear(@cache_name)
  end

  # Private functions

  defp resolver(resolver_fn, name) do
    # Caching is only possible for query resolvers for now. Field resolvers are
    # not supported, because they are scoped on their root object, we can't get
    # a good, general cache key for arbitrary root objects
    fn %{}, args, resolution ->
      {_, value} =
        Cachex.fetch(@cache_name, cache_key(name, args, resolution), fn ->
          {:commit, resolver_fn.(%{}, args, resolution)}
        end)

      value
    end
  end

  defp cache_key(name, args, resolution \\ %{}) do
    args_hash =
      args
      |> convert_values()
      |> Poison.encode!()
      |> sha256()

    requested_fields_hash =
      resolution
      |> requested_fields()
      |> sha256()

    {name, args_hash, requested_fields_hash}
  end

  defp convert_values(args) do
    args
    |> Enum.map(fn
      {k, %DateTime{} = v} ->
        {k, div(DateTime.to_unix(v, :millisecond), @ttl)}

      pair ->
        pair
    end)
    |> Map.new()
  end

  defp sha256(data) do
    :crypto.hash(:sha256, data)
    |> Base.encode16()
  end

  defp requested_fields(resolution) when resolution == %{}, do: []

  defp requested_fields(resolution) do
    resolution.definition.selections
    |> Enum.map(&Map.get(&1, :name))
  end
end
