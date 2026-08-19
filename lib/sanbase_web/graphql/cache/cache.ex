defmodule SanbaseWeb.Graphql.Cache do
  @moduledoc ~s"""
  Provides the macro `cache_resolve` that replaces the Absinthe's `resolve` and
  caches the result of the resolver for a some time instead of precalculating itt
  each time.
  """

  alias __MODULE__, as: CacheMod
  alias SanbaseWeb.Graphql.CachexProvider, as: CacheProvider

  @ttl 300
  @max_ttl_offset 120
  @cache_name :graphql_cache

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
            convert_values: 2,
            generate_source_args: 1}

  def child_spec(opts) do
    CacheProvider.child_spec(opts)
  end

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

  Just like `resolve` coming from Absinthe, `cache_resolve` supports the `{:ok, value}`
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

  @doc "Clears the whole cache. Slow."
  def clear_all(), do: CacheProvider.clear_all(@cache_name)

  @doc " The size of the cache in megabytes"
  def size(), do: CacheProvider.size(@cache_name)

  @doc """
  The true byte size of all compressed values in the cache.

  O(n) table walk (~40ms per 200k entries) — meant to be called on demand,
  never from hot paths or tight polling loops. See `CachexProvider.payload_bytes/1`
  for why this cannot be a maintained counter.
  """
  def payload_bytes(), do: CacheProvider.payload_bytes(@cache_name)

  @doc "The number of entries in the cache"
  def count(), do: CacheProvider.count(@cache_name)

  @doc "The the value for a given key form the cache"
  def get(key), do: CacheProvider.get(@cache_name, key)

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
    fn
      %{} = root, args, resolution ->
        fun = fn -> resolver_fn.(root, args, resolution) end

        # A non-empty root object contributes some of its arguments to the key.
        additional_args = Map.take(root, [:id, :slug, :word])

        # resolution.source holds the arguments passed to a parent object. To cache
        # {getMetric(metric: "nvt") {timeseriesData(...)}} correctly, the key must include
        # `metric` from the parent's args.
        args_from_source = generate_source_args(resolution.source)

        # `include_subscription_in_key: true` puts the current product and plan in the key,
        # for results depending on the user's subscription such as metric restrictions.
        args_from_subscription = generate_subscription_args(resolution.context, opts)
        args_from_user_details = generate_user_details_args(resolution.context, opts)

        cache_key =
          cache_key(
            {name, additional_args, args_from_source, args_from_subscription,
             args_from_user_details},
            args,
            opts
          )

        # Caching is disabled per query: all_projects_by_function sets the
        # do_not_cache_query: true process key when base_projects depends on a watchlist.
        # Only resolvers passing `honor_do_no_cache_flag: true` react to it, so it disables
        # the caching that matters rather than all of it.
        skip_cache? =
          Keyword.get(opts, :honor_do_not_cache_flag, false) and
            Process.get(:do_not_cache_query) == true

        case skip_cache? do
          true -> fun.()
          false -> get_or_store(cache_key, fun)
        end
    end
  end

  defp generate_user_details_args(%{auth: %{current_user: user}}, opts) do
    case Keyword.get(opts, :include_user_details_in_key, false) do
      false ->
        []

      true ->
        [
          access_to_experiemental_metrics: user.metric_access_level,
          available_metrics_lookback_days: user.available_metrics_lookback_days
        ]
    end
  end

  defp generate_user_details_args(_context, _opts), do: []

  defp generate_subscription_args(context, opts) do
    case Keyword.get(opts, :include_subscription_in_key, false) do
      false ->
        []

      true ->
        [plan: get_in(context, [:auth, :plan]), product_id: get_in(context, [:product_id])]
    end
  end

  defp generate_source_args(source) do
    case source do
      # Make sure to use both metric and version when using version
      %{metric: _, version: _} = source -> source
      %{id: id} when not is_nil(id) -> id
      %{slug: slug} when not is_nil(slug) -> slug
      %{word: word} when not is_nil(word) -> word
      _ -> source
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

  # `cache_modify_middleware` runs only inside `get_or_store`, which serializes concurrent
  # access, so calling `store` explicitly is race-free.
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
    base_ttl = args[:caching_params][:base_ttl] || Keyword.get(opts, :ttl, @ttl)

    max_ttl_offset =
      args[:caching_params][:max_ttl_offset] ||
        Keyword.get(opts, :max_ttl_offset, @max_ttl_offset)

    base_ttl = Enum.max([base_ttl, 1])
    max_ttl_offset = Enum.max([max_ttl_offset, 1])

    # Used to randomize the TTL for lists of objects like list of projects
    additional_args = Map.take(args, [:slug, :id, :word])

    # Using phash2 as a random number between 0 and max_ttl_offset is needed.
    # collisions are allowed and do not lead to errors
    ttl = base_ttl + ({name, additional_args} |> :erlang.phash2(max_ttl_offset))

    if args[:caching_params] do
      # This is used in the Absinthe's before_send function
      Process.put(:__change_absinthe_before_send_caching_ttl__, ttl)
    end

    args = args |> convert_values(ttl)

    # The datetime bucket is included so a never-released lock cannot pin the key forever -
    # it changes after base_ttl + max_ttl_offset. The 0-180 offset derived from the query
    # and slug spreads expirations and avoids a thundering herd.
    bucket_ttl = base_ttl + max_ttl_offset + :erlang.phash2({name, args}, 180)
    current_bucket = convert_values(DateTime.utc_now(), bucket_ttl)

    cache_key =
      {__MODULE__, current_bucket, :__internal_graphql_api_caching__, name, args}
      |> Sanbase.Cache.hash()

    {cache_key, ttl}
  end

  # Values as used in the cache. `%DateTime{}` is special-cased so all datetimes in a
  # @ttl sized window are treated the same.
  defp convert_values(%DateTime{} = v, ttl), do: div(DateTime.to_unix(v, :second), ttl)
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
