defmodule SanbaseWeb.Graphql.Cache do
  @moduledoc ~s"""
  Provides the macro `cache_resolve` that replaces the Absinthe's `resolve` and
  caches the result of the resolver for a some time instead of precalculating itt
  each time.
  """
  require Logger

  @ttl 300
  @max_ttl_offset 120
  @cache_name :graphql_cache

  @compile :inline_list_funcs
  @compile {:inline,
            wrap: 2,
            wrap: 3,
            from: 2,
            resolver: 3,
            store: 2,
            store: 3,
            get_or_store: 2,
            get_or_store: 3,
            cache_modify_middleware: 3,
            cache_key: 2,
            convert_values: 2}

  alias __MODULE__, as: CacheMod
  alias SanbaseWeb.Graphql.ConCacheProvider, as: CacheProvider

  @doc ~s"""
  Macro that's used instead of Absinthe's `resolve`. This resolver can perform
  the following operations:
  1. Get the value from a cache if it is persisted. The resolver function is not
  evaluated at all in this case
  2. Evaluate the resolver function and store the value in the cache if it is
  not present there
  3. Handle the `Absinthe.Middlewar.Async` and `Absinthe.Middleware.Dataloader`
  middlewares. In order to handle them, the functions that executes the actual
  evaluation is wrapped in a function that handles the cache interactions

  There are 2 options for the passed function:
  1. It can be a captured named function because its name is extracted
  and used in the cache key.
  2. If the function is anonymous or a different name should be used, a second
  parameter with that name must be passed.

  Just like `resolve` comming from Absinthe, `cache_resolve` supports the `{:ok, value}`
  and `{:error, reason}` result tuples. The `:ok` tuples are cached while the `:error`
  tuples are not.

  But `cache_resolve` knows how to handle a third type of response format. When
  `{:nocache, {:ok, value}}` is returned as the result the cache does **not** cache
  the value and just returns `{:ok, value}`. This is particularly useful when
  the result can't be constructed but returning an error will crash the whole query.
  In such cases a default/filling value can be passed (0, nil, "No data", etc.)
  and the next query will try to resolve it again
  """

  defmacro cache_resolve(captured_mfa_ast, opts \\ []) do
    quote do
      middleware(
        Absinthe.Resolution,
        CacheMod.from(unquote(captured_mfa_ast), unquote(opts))
      )
    end
  end

  @doc ~s"""
  Exposed as sometimes it can be useful to use it outside the macros.

  Gets a function, name and arguments and returns a new function that:
  1. On execution checks if the value is present in the cache and returns it
  2. If it's not in the cache it gets executed and the value is stored in the cache.

  NOTE: `cached_func` is a function with arity 0. That means if you want to use it
  in your code and you want some arguments you should use it like this:
    > Cache.wrap(
    >   fn ->
    >     fetch_last_price_record(pair)
    >   end,
    >   :fetch_price_last_record, %{pair: pair}
    > ).()
  """
  def wrap(cached_func, name, args \\ %{}, opts \\ []) do
    fn ->
      CacheProvider.get_or_store(
        @cache_name,
        cache_key(name, args, opts),
        cached_func,
        &cache_modify_middleware/3
      )
    end
  end

  @doc ~s"""
  Clears the whole cache. Slow.
  """
  def clear_all() do
    CacheProvider.clear_all(@cache_name)
  end

  @doc ~s"""
  The size of the cache in megabytes
  """
  def size() do
    CacheProvider.size(@cache_name, :megabytes)
  end

  def get(key) do
    CacheProvider.get(@cache_name, key)
  end

  @doc false
  def from(captured_mfa, opts) when is_function(captured_mfa) do
    # Public so it can be used by the resolve macros. You should not use it.
    case Keyword.pop(opts, :fun_name) do
      {nil, opts} ->
        fun_name = captured_mfa |> :erlang.fun_info() |> Keyword.get(:name)
        resolver(captured_mfa, fun_name, opts)

      {fun_name, opts} ->
        resolver(captured_mfa, fun_name, opts)
    end
  end

  # Private functions

  defp resolver(resolver_fn, name, opts) do
    # Works only for top-level resolvers and fields with root object that has `id` field
    fn
      %{id: id} = root, args, resolution ->
        fun = fn -> resolver_fn.(root, args, resolution) end

        cache_key({name, id, resolution.source}, args, opts)
        |> get_or_store(fun)

      %{word: word} = root, args, resolution ->
        fun = fn -> resolver_fn.(root, args, resolution) end

        cache_key({name, word, resolution.source}, args, opts)
        |> get_or_store(fun)

      %{}, args, resolution ->
        fun = fn -> resolver_fn.(%{}, args, resolution) end

        cache_key({name, resolution.source}, args, opts)
        |> get_or_store(fun)
    end
  end

  def store(cache_name \\ @cache_name, cache_key, value) do
    CacheProvider.store(cache_name, cache_key, value)
  end

  def get_or_store(cache_name \\ @cache_name, cache_key, resolver_fn) do
    CacheProvider.get_or_store(
      cache_name,
      cache_key,
      resolver_fn,
      &cache_modify_middleware/3
    )
  end

  # `cache_modify_middleware` is called only from withing `get_or_store` that
  # guarantees that it will be executed only once if it is accessed concurently.
  # This is way it is safe to use `store` explicitly without worrying about race
  # conditions
  defp cache_modify_middleware(cache_name, cache_key, {:ok, value} = result) do
    CacheProvider.store(cache_name, cache_key, result)

    {:ok, value}
  end

  defp cache_modify_middleware(
         cache_name,
         cache_key,
         {:middleware, Absinthe.Middleware.Async = midl, {fun, opts}}
       ) do
    caching_fun = fn ->
      CacheProvider.get_or_store(cache_name, cache_key, fun, &cache_modify_middleware/3)
    end

    {:middleware, midl, {caching_fun, opts}}
  end

  defp cache_modify_middleware(
         cache_name,
         cache_key,
         {:middleware, Absinthe.Middleware.Dataloader = midl, {loader, callback}}
       ) do
    caching_callback = fn loader_arg ->
      CacheProvider.get_or_store(
        cache_name,
        cache_key,
        fn -> callback.(loader_arg) end,
        &cache_modify_middleware/3
      )
    end

    {:middleware, midl, {loader, caching_callback}}
  end

  # Helper functions

  def cache_key(name, args, opts \\ []) do
    base_ttl = Keyword.get(opts, :ttl, @ttl)
    max_ttl_offset = Keyword.get(opts, :max_ttl_offset, @max_ttl_offset)
    slug = Map.get(args, :slug, "")

    ttl = base_ttl + ({name, slug} |> :erlang.phash2(max_ttl_offset))

    args =
      args
      |> convert_values(ttl)

    cache_key =
      [name, args]
      |> :erlang.phash2()

    {cache_key, ttl}
  end

  # Convert the values for using in the cache. A special treatement is done for
  # `%DateTime{}` so all datetimes in a @ttl sized window are treated the same
  defp convert_values(%DateTime{} = v, ttl) do
    div(DateTime.to_unix(v, :second), ttl)
  end

  defp convert_values(%_{} = v, _), do: Map.from_struct(v)

  defp convert_values(args, ttl) when is_list(args) or is_map(args) do
    args
    |> Enum.map(fn
      {k, v} ->
        [k, convert_values(v, ttl)]

      data ->
        convert_values(data, ttl)
    end)
  end

  defp convert_values(v, _), do: v
end
