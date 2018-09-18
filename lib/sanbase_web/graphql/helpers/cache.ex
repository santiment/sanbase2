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

  defmacro cache_resolve_async(captured_mfa_ast) do
    quote do
      middleware(
        Absinthe.Resolution,
        CacheMod.middleware_from(unquote(captured_mfa_ast))
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
        CacheMod.middleware_from(unquote(captured_mfa_ast))
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

  @doc false
  def from(captured_mfa) when is_function(captured_mfa) do
    # Public so it can be used by the resolve macros. You should not use it.
    fun_name = captured_mfa |> captured_mfa_name()

    resolver(captured_mfa, fun_name)
  end

  @doc false
  def from(fun, fun_name) when is_function(fun) do
    # Public so it can be used by the resolve macros. You should not use it.
    resolver(fun, fun_name)
  end

  @doc false
  def middleware_from(captured_mfa) when is_function(captured_mfa) do
    # Public so it can be used by the resolve macros. You should not use it.
    fun_name = captured_mfa |> captured_mfa_name()
    middleware_resolver(captured_mfa, fun_name)
  end

  # Private functions

  defp resolver(resolver_fn, name) do
    # Works only for top-level resolvers and fields with root object Project
    fn
      %{id: id} = root, args, resolution ->
        fun = fn -> resolver_fn.(root, args, resolution) end

        cache_key({name, id}, args)
        |> get_or_store(fun)

      %{}, args, resolution ->
        fun = fn -> resolver_fn.(%{}, args, resolution) end

        cache_key(name, args)
        |> get_or_store(fun)
    end
  end

  # ==== ASYNC ====
  # The actual work for the async cache resolver is done here.
  #
  # The most important part is how the cache is actually populated. The resolver
  # returns a `{:middleware, Absinthe.Middleware.Async, {fun, opts}}` tuple.
  # This is NOT the final result so it cannot be used. Instead, `fun` is replaced
  # by a function that does the caching.
  # That works because `fun` is always a function with zero arguments, which
  # when executed (async) returns the actual result.
  #
  # ==== DATALOADER ====
  # The actual work for the dataloader cache resolver is done here.
  #
  # The most important part is how the cache is actually populated. The resolver
  # returns a `{:middleware, Absinthe.Middleware.Dataloader, {loader, callback}}` tuple.
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
  defp middleware_resolver(resolver_fn, name) do
    # Works only for top-level resolvers and fields with root object that has `id` attribute
    fn
      %{id: id} = root, args, resolution ->
        fun = fn -> resolver_fn.(root, args, resolution) end

        cache_key({name, id}, args)
        |> get_or_store_middleware(fun)

      %{}, args, resolution ->
        fun = fn -> resolver_fn.(%{}, args, resolution) end

        cache_key(name, args)
        |> get_or_store_middleware(fun)
    end
  end

  # Calculate the cache key from a given name and arguments.

  defp get_or_store(cache_key, resolver_fn) do
    {:ok, value} =
      ConCache.get_or_store(@cache_name, cache_key, fn ->
        {:ok, resolver_fn.()}
      end)

    value
  end

  defp get_or_store_middleware(cache_key, resolver_fn) do
    case ConCache.get(@cache_name, cache_key) do
      nil ->
        cache_modify_middleware(cache_key, resolver_fn.())

      # Wrapped in a tuple to distinguish value = nil from not having a record
      # If we have the result in the cache the middleware tuple is skipped
      {:ok, value} ->
        value
    end
  end

  # Used because we disable the Async middleware in tests
  defp cache_modify_middleware(cache_key, {:ok, value}) do
    ConCache.put(@cache_name, cache_key, {:ok, value})

    {:ok, value}
  end

  defp cache_modify_middleware(
         cache_key,
         {:middleware, Absinthe.Middleware.Async = midl, {fun, opts}}
       ) do
    caching_fun = fn ->
      value = fun.()
      ConCache.put(@cache_name, cache_key, {:ok, value})

      value
    end

    {:middleware, midl, {caching_fun, opts}}
  end

  defp cache_modify_middleware(
         cache_key,
         {:middleware, Absinthe.Middleware.Dataloader = midl, {loader, callback}}
       ) do
    caching_callback = fn loader_arg ->
      value = callback.(loader_arg)
      ConCache.put(@cache_name, cache_key, {:ok, value})

      value
    end

    {:middleware, midl, {loader, caching_callback}}
  end

  defp cache_key(name, args) do
    args_hash =
      args
      |> convert_values()
      |> Jason.encode!()
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
