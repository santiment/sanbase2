defmodule Sanbase.Cache do
  @behaviour Sanbase.Cache.Behaviour
  @cache_name :sanbase_cache
  @max_cache_ttl 86_400

  @compile {:inline, get_or_store_isolated: 5}

  @type opts :: [return_nocache: boolean()]

  @impl Sanbase.Cache.Behaviour
  def child_spec(opts) do
    Supervisor.child_spec(
      {ConCache,
       [
         name: Keyword.fetch!(opts, :name),
         ttl_check_interval: Keyword.get(opts, :ttl_check_interval, :timer.seconds(5)),
         global_ttl: Keyword.get(opts, :global_ttl, :timer.minutes(5)),
         acquire_lock_timeout: Keyword.get(opts, :acquire_lock_timeout, 60_000)
       ]},
      id: Keyword.fetch!(opts, :id)
    )
  end

  @impl Sanbase.Cache.Behaviour
  def hash(data) do
    data = if contains_request_context?(data), do: strip_request_context(data), else: data

    :crypto.hash(:sha256, :erlang.term_to_binary(data))
    |> Base.encode64()
  end

  # `Sanbase.RequestContext` is threaded as a `:context` keyword option
  # through data-layer call sites for privacy masking. The context's
  # presence must not change cache keys, otherwise every protected vs
  # non-protected user would miss the cache for the same query. Walk
  # the input tree and drop only `:context` values that actually contain
  # `%RequestContext{}` instances before hashing.
  # Other structs are preserved as-is — rewriting them as plain maps
  # would change every existing cache key on deploy.
  #
  # Hot-path: `Cache.hash/1` runs on every cache key. The `:context` opt
  # is added only on migrated call sites, so the common case is a tree
  # with neither `:context` keyword pairs nor nested `%RequestContext{}`
  # structs. `contains_request_context?/1` is a walk-without-allocate
  # probe; only when it returns true do we rebuild the tree.
  defp contains_request_context?(%Sanbase.RequestContext{}), do: true

  defp contains_request_context?(list) when is_list(list) do
    Enum.any?(list, &contains_request_context?/1)
  end

  defp contains_request_context?(%_{}), do: false

  defp contains_request_context?(tuple) when is_tuple(tuple) do
    contains_request_context_in_tuple?(tuple, tuple_size(tuple), 0)
  end

  defp contains_request_context?(map) when is_map(map) do
    Enum.any?(map, fn {_k, v} -> contains_request_context?(v) end)
  end

  defp contains_request_context?(_), do: false

  defp contains_request_context_in_tuple?(_tuple, size, size), do: false

  defp contains_request_context_in_tuple?(tuple, size, idx) do
    contains_request_context?(:erlang.element(idx + 1, tuple)) or
      contains_request_context_in_tuple?(tuple, size, idx + 1)
  end

  defp strip_request_context(%Sanbase.RequestContext{}), do: :_request_context

  defp strip_request_context(list) when is_list(list) do
    if Keyword.keyword?(list) do
      Enum.flat_map(list, fn
        {:context, %Sanbase.RequestContext{}} -> []
        {key, value} -> [{key, strip_request_context(value)}]
      end)
    else
      Enum.map(list, &strip_request_context/1)
    end
  end

  defp strip_request_context(%_{} = struct), do: struct

  defp strip_request_context(tuple) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.map(&strip_request_context/1)
    |> List.to_tuple()
  end

  defp strip_request_context(map) when is_map(map) do
    map
    |> Enum.flat_map(fn
      {:context, %Sanbase.RequestContext{}} -> []
      {k, v} -> [{k, strip_request_context(v)}]
    end)
    |> Map.new()
  end

  defp strip_request_context(other), do: other

  def name, do: @cache_name

  @impl Sanbase.Cache.Behaviour
  def size(cache) do
    bytes_size = :ets.info(ConCache.ets(cache), :memory) * :erlang.system_info(:wordsize)
    (bytes_size / (1024 * 1024)) |> Float.round(2)
  end

  @impl Sanbase.Cache.Behaviour
  def count(cache) do
    :ets.info(ConCache.ets(cache), :size)
  end

  def clear(cache \\ @cache_name, key) do
    ConCache.delete(cache, key)
  end

  @impl Sanbase.Cache.Behaviour
  def clear_all(cache \\ @cache_name)

  def clear_all(cache) do
    cache
    |> ConCache.ets()
    |> :ets.tab2list()
    |> Enum.each(fn {key, _} -> ConCache.delete(cache, key) end)
  end

  @impl Sanbase.Cache.Behaviour
  def get(cache \\ @cache_name, key)

  def get(cache, key) do
    case ConCache.get(cache, true_key(key)) do
      {:stored, value} -> value
      nil -> nil
    end
  end

  @impl Sanbase.Cache.Behaviour
  def store(cache \\ @cache_name, key, value)

  def store(cache, key, value) do
    case value do
      {:error, _} ->
        :ok

      value ->
        cache_item(cache, key, {:stored, value})
    end
  end

  @doc ~s"""
  Get the value from the cache, or, if it does not exist there, compute it after
  locking the key. This locking guarantees that if 100 concurrent processes try
  to get this value, only one of them will do the actual computation and all other
  will wait. This greatly reduces the DB load that will otherwise occur.

  A value wrapped in `{:nocache, {:ok, _}}` is never written to the cache. By
  default the tag is stripped before returning so callers receive `{:ok, _}`.
  Pass `return_nocache: true` to preserve the tag — required when an outer cache
  layer wraps this call, otherwise the outer layer sees a plain `{:ok, _}` and
  caches it permanently, defeating the `:nocache` signal.

  # TODO (2026-04-23): audit `:nocache` propagation across all `get_or_store`
  # callers.
  #
  # Change: `get_or_store/3` gained an `opts` arg with `return_nocache: true`.
  # Default remains "strip the tag" to preserve historical behavior for the ~52
  # existing callers. Only the `Sanbase.Metric` facade fns (timeseries/histogram/
  # table) were flipped to preserve, because the resolver wraps them in
  # `RehydratingCache` and the stripped `{:ok, _}` was being cached permanently
  # — a latent bug that silently defeated `:nocache` retries.
  #
  # Anywhere an inner fn can return `{:nocache, {:ok, _}}` AND an outer cache
  # (Sanbase.Cache, RehydratingCache, CachexProvider) wraps the call, the outer
  # needs `return_nocache: true`. Otherwise the same latent bug applies.
  #
  # Possible follow-up: swap opt-in tag preservation for a `Process.put`-based
  # signal like `SanbaseWeb.Graphql.CachexProvider` — set a process-dict flag on
  # `:nocache` and let the request pipeline read it at the top. Avoids threading
  # the opt through every layer, but only works inside a request-scoped process
  # (GraphQL resolution). Not universally applicable because `Sanbase.Cache` is
  # also used outside request context.
  """
  @impl Sanbase.Cache.Behaviour
  def get_or_store(cache \\ @cache_name, key, func, opts \\ [])

  def get_or_store(cache, key, func, opts) do
    true_key = true_key(key)

    case ConCache.get(cache, true_key) do
      {:stored, value} ->
        value

      _ ->
        get_or_store_isolated(cache, key, true_key, func, opts)
    end
  end

  defp get_or_store_isolated(cache, key, true_key, func, opts) do
    # This function is to be executed inside ConCache.isolated/3 call.
    # This isolated call locks the access for that key before doing anything else
    # Doing this ensures that the case where another process modified the key
    # before in the time between the previous check and the locking.
    fun = fn ->
      case ConCache.get(cache, true_key) do
        {:stored, value} ->
          value

        _ ->
          execute_and_maybe_cache_function(cache, key, func, opts)
      end
    end

    ConCache.isolated(cache, true_key, fun)
  end

  defp execute_and_maybe_cache_function(cache, key, func, opts) do
    # Execute the function and if it returns :ok tuple cache it
    # Errors are not cached. Also, caching can be manually disabled by
    # wrapping the result in a :nocache tuple
    case func.() do
      {:error, _} = error ->
        error

      {:nocache, {:ok, _result} = value} = nocache ->
        if Keyword.get(opts, :return_nocache, false), do: nocache, else: value

      value ->
        cache_item(cache, key, {:stored, value})
        value
    end
  end

  defp cache_item(cache, {key, ttl}, value) when is_integer(ttl) and ttl <= @max_cache_ttl do
    ConCache.put(cache, key, %ConCache.Item{value: value, ttl: :timer.seconds(ttl)})
  end

  defp cache_item(cache, key, value) do
    ConCache.put(cache, key, value)
  end

  defp true_key({key, ttl}) when is_integer(ttl) and ttl <= @max_cache_ttl, do: key
  defp true_key(key), do: key
end
