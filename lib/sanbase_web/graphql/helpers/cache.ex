defmodule SanbaseWeb.Graphql.Helpers.Cache do
  @ttl :timer.minutes(5)
  def from(captured_mfa) when is_function(captured_mfa) do
    fun_name =
      captured_mfa
      |> :erlang.fun_info()
      |> Keyword.get(:name)

    captured_mfa
    |> resolver(fun_name)
  end

  def resolver(resolver_fn, name) do
    # Caching is only possible for query resolvers for now. Field resolvers are
    # not supported, because they are scoped on their root object, we can't get
    # a good, general cache key for arbitrary root objects
    fn %{}, args, resolution ->
      {_, value} =
        Cachex.fetch(:graphql_cache, cache_key(name, args), fn ->
          {:commit, resolver_fn.(%{}, args, resolution)}
        end)

      value
    end
  end

  def func(cached_func, name, args \\ %{}) do
    fn ->
      {_, value} =
        Cachex.fetch(:graphql_cache, cache_key(name, args), fn ->
          {:commit, cached_func.()}
        end)

      value
    end
  end

  defp cache_key(name, args) do
    args_hash =
      args
      |> convert_values
      |> Poison.encode!()
      |> sha256

    {name, args_hash}
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
end
