defmodule SanbaseWeb.Graphql.Helpers.Cache do
  require Logger

  @ttl :timer.minutes(5)
  @cache_name :graphql_cache

  alias __MODULE__, as: CacheMod

  defmacro cache_resolve(captured_mfa_ast) do
    quote do
      middleware(
        Absinthe.Resolution,
        CacheMod.from(unquote(captured_mfa_ast))
      )
    end
  end

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
        Cachex.fetch(@cache_name, cache_key(name, args), fn ->
          Logger.info(
            "Caching a new value in Graphql Cache. Current cache size: #{size(:megabytes)}mb"
          )

          {:commit, cached_func.()}
        end)

      value
    end
  end

  def clear_all() do
    Cachex.clear(@cache_name)
  end

  def size(:megabytes) do
    bytes_size = :ets.info(:graphql_cache, :memory) * :erlang.system_info(:wordsize)
    (bytes_size / (1024 * 1024)) |> Float.round(2)
  end

  # Private functions

  defp resolver(resolver_fn, name) do
    # Caching is only possible for query resolvers for now. Field resolvers are
    # not supported, because they are scoped on their root object, we can't get
    # a good, general cache key for arbitrary root objects
    fn %{}, args, resolution ->
      {_, value} =
        Cachex.fetch(@cache_name, cache_key(name, args), fn ->
          {:commit, resolver_fn.(%{}, args, resolution)}
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
