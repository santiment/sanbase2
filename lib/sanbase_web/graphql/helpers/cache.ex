defmodule SanbaseWeb.Graphql.Helpers.Cache do
  require Logger

  @ttl :timer.minutes(5)
  @cache_name :graphql_cache

  alias __MODULE__, as: CacheMod

  @doc ~s"""
    Macro that's used instead of Absinthe's `resolve`. The value of the resolver is
    1. get from a cache if it exists there
    2. calculated and stored in the cache if it does not exist

    The value of `captured_mfa_ast` when executed MUST be a concrete value but not
    a new middleware.

    The function MUST be a captured named function because its name is extracted
    and used in the cache key.
  """
  defmacro cache_resolve(captured_mfa_ast) do
    quote do
      middleware(
        Absinthe.Resolution,
        CacheMod.from(unquote(captured_mfa_ast))
      )
    end
  end

  @doc ~s"""
    Macro that's used instead of Absinthe's `resolve`. The value of the resolver is
    1. Get from a cache if it exists there
    2. Calculated and stored in the cache if it does not exist

    The value of `captured_mfa_ast` when executed MUST be a concrete value but not
    a new middleware.

    The function's name is not used but instead `fun_name` is used in the cache key
  """
  defmacro cache_resolve(captured_mfa_ast, fun_name) do
    quote do
      middleware(
        Absinthe.Resolution,
        CacheMod.from(unquote(captured_mfa_ast), unquote(fun_name))
      )
    end
  end

  @doc ~s"""
    Macro that's used instead of Absinthe's `resolve`. The value of the resolver is
    1. Get from a cache if it exists there
    2. Calculated at a later point in time (when the middleware is executed)
    and stored in the cache if it does not exist

    The value of `captured_mfa_ast` MUST be a dataloader middleware tuple with three elements
    `{:middleware, Absinthe.Middleware.Dataloder, callback}` where `callback` is a
    function with arity 1 that accepts `loader` as a single parameter.

    The function MUST be a captured named function because its name is extracted
    and used in the cache key.
  """
  defmacro cache_resolve_dataloader(captured_mfa_ast) do
    quote do
      middleware(
        Absinthe.Resolution,
        CacheMod.dataloader_from(unquote(captured_mfa_ast))
      )
    end
  end

  @doc ~s"""
    Exposed as
    sometimes it can be useful to use it outside the macros.

    Gets a function, name and arguments and returns a new function that:
    1. On execution checks if the value is present in the cache and returns it
    2. If it's not in the cache it gets executed and the value is stored in the cache.

    NOTE: `cached_func` is a function with arity 0. That means if you want to use it
    in your code and you want some arguments you should use it like this:
      > Cache.func(
      >   fn ->
      >     fetch_last_price_record(pair)
      >   end,
      >   :fetch_price_last_record, %{pair: pair}
      > ).()
  """
  def func(cached_func, name, args \\ %{}) do
    fn ->
      {:ok, value} =
        ConCache.get_or_store(@cache_name, cache_key(name, args), fn ->
          {:ok, cached_func.()}
        end)

      value
    end
  end

  @doc ~s"""
    Clears the whole cache. Slow.
  """
  def clear_all() do
    @cache_name
    |> ConCache.ets()
    |> :ets.tab2list()
    |> Enum.each(fn {key, _} -> ConCache.delete(@cache_name, key) end)
  end

  @doc ~s"""
    The size of the cache in megabytes
  """
  def size(:megabytes) do
    bytes_size = :ets.info(ConCache.ets(@cache_name), :memory) * :erlang.system_info(:wordsize)
    (bytes_size / (1024 * 1024)) |> Float.round(2)
  end

  # Public so it can be used by the resolve macros. You should not use it.
  def from(captured_mfa) when is_function(captured_mfa) do
    fun_name = captured_mfa |> captured_mfa_name()

    resolver(captured_mfa, fun_name)
  end

  # Public so it can be used by the resolve macros. You should not use it.
  def from(fun, fun_name) when is_function(fun) do
    resolver(fun, fun_name)
  end

  # Public so it can be used by the resolve macros. You should not use it.
  def dataloader_from(captured_mfa) when is_function(captured_mfa) do
    fun_name = captured_mfa |> captured_mfa_name()

    dataloader_resolver(captured_mfa, fun_name)
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

  # The actual work for the dataloader cache resolver is done here.
  #
  # The most important part is how the cache is actually populated. The resolver
  # returns a `{:middleware, Absinthe.Middleware.Dataloader, callback}` tuple.
  # This is NOT the final result so it cannot be used. Instead, `callback` is replaced
  # by a function that does the caching.
  # That works because `callback` is always a function with one argument `loader`, which
  # when executed (after `Dataloader.run` is called from the middleware) returns the
  # actual result.
  #
  # The modified callback internally calls the original callback, passing it the argument,
  # stores the value in the cache and returns the value. From the outside it works the same
  # as the original callback
  #
  # Because Elixir's lambdas are correctly implemented, we can fetch what's needed
  # from the context to use it for `cache_key`
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
              ConCache.put(@cache_name, cache_key, {:ok, value})

              value
            end

            {:middleware, midl, {loader, caching_callback}}

          # Wrap in a tuple to distinguish value = nil from not having a record
          {:ok, value} ->
            value
        end

      %{}, args, resolution ->
        cache_key = cache_key(name, args)

        case ConCache.get(@cache_name, cache_key) do
          nil ->
            {:middleware, midl, {loader, callback}} = resolver_fn.(%{}, args, resolution)

            caching_callback = fn loader_arg ->
              value = callback.(loader_arg)
              ConCache.put(@cache_name, cache_key, {:ok, value})

              value
            end

            {:middleware, midl, {loader, caching_callback}}

          # Wrap in a tuple to distinguish value = nil from not having a record
          {:ok, value} ->
            value
        end
    end
  end

  # Calculate the cache key from a given name and arguments.
  defp cache_key(name, args) do
    args_hash =
      args
      |> convert_values()
      |> Poison.encode!()
      |> sha256()

    {name, args_hash}
  end

  # Convert the values for using in the cache. A special treatement is done for
  # `%DateTime{}` so all datetimes in a @ttl sized window are treated the same
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
