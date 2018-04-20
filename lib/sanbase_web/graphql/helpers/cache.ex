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

  defmacro cache_resolve_dataloader(captured_mfa_ast) do
    quote do
      middleware(
        Absinthe.Resolution,
        CacheMod.dataloader_from(unquote(captured_mfa_ast))
      )
    end
  end

  def from(captured_mfa) when is_function(captured_mfa) do
    fun_name = captured_mfa |> captured_mfa_name()

    captured_mfa
    |> resolver(fun_name)
  end

  def dataloader_from(captured_mfa) when is_function(captured_mfa) do
    fun_name = captured_mfa |> captured_mfa_name()

    captured_mfa
    |> dataloader_resolver(fun_name)
  end

  def from(fun, fun_name) when is_function(fun) do
    fun
    |> resolver(fun_name)
  end

  def func(cached_func, name, args \\ %{}) do
    fn ->
      ConCache.get_or_store(@cache_name, cache_key(name, args), fn ->
        cached_func.()
      end)
    end
  end

  def clear_all() do
    @cache_name
    |> ConCache.ets()
    |> :ets.tab2list()
    |> Enum.each(fn {key, _} -> ConCache.delete(@cache_name, key) end)
  end

  def size(:megabytes) do
    bytes_size = :ets.info(ConCache.ets(@cache_name), :memory) * :erlang.system_info(:wordsize)
    (bytes_size / (1024 * 1024)) |> Float.round(2)
  end

  # Private functions

  defp resolver(resolver_fn, name) do
    # Works only for top-level resolvers and fields with root object Project
    fn
      %Sanbase.Model.Project{id: id} = project, args, resolution ->
        {:ok, value} =
          ConCache.get_or_store(@cache_name, cache_key({name, id}, args), fn ->
            {:ok, resolver_fn.(project, args, resolution)}
          end)

        value

      %{}, args, resolution ->
        {:ok, value} =
          ConCache.get_or_store(@cache_name, cache_key(name, args), fn ->
            {:ok, resolver_fn.(%{}, args, resolution)}
          end)

        value
    end
  end

  defp dataloader_resolver(resolver_fn, name) do
    # Works only for top-level resolvers and fields with root object Project
    fn
      %Sanbase.Model.Project{id: id} = project, args, resolution ->
        cache_key = cache_key({name, id}, args)

        case ConCache.get(@cache_name, cache_key) do
          nil ->
            {:middleware, midl, {loader, callback}} = resolver_fn.(project, args, resolution)

            caching_callback = fn loader ->
              value = callback.(loader)
              ConCache.put(@cache_name, cache_key, value)

              value
            end

            {:middleware, midl, {loader, caching_callback}}

          value ->
            value
        end

      %{}, args, resolution ->
        cache_key = cache_key(name, args)

        case ConCache.get(@cache_name, cache_key) do
          nil ->
            {:middleware, midl, {loader, callback}} = resolver_fn.(%{}, args, resolution)

            caching_callback = fn loader_arg ->
              value = callback.(loader_arg)
              ConCache.put(@cache_name, cache_key, value)

              value
            end

            {:middleware, midl, {loader, caching_callback}}

          value ->
            value
        end
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

  defp captured_mfa_name(captured_mfa) do
    captured_mfa
    |> :erlang.fun_info()
    |> Keyword.get(:name)
  end
end
