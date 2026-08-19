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
         # Above the ClickHouse budget, as in `CachexProvider`: a lock wait
         # must outlast the work it waits on. See docs/timeouts.md.
         acquire_lock_timeout: Keyword.get(opts, :acquire_lock_timeout, 102_000)
       ]},
      id: Keyword.fetch!(opts, :id)
    )
  end

  @impl Sanbase.Cache.Behaviour
  def hash(data) do
    data
    |> Sanbase.Cache.RequestContextStripper.strip()
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode64()
  end

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

  # TODO (2026-04-23): audit `:nocache` propagation across all `get_or_store` callers.
  #
  # `get_or_store/3` gained an `opts` arg with `return_nocache: true`. The default still
  # strips the tag, preserving the behavior the ~52 existing callers rely on. Only the
  # `Sanbase.Metric` facade fns (timeseries/histogram/table) preserve it, because the
  # resolver wraps them in `RehydratingCache` and the stripped `{:ok, _}` was cached
  # permanently - a latent bug that silently defeated `:nocache` retries. The same applies
  # anywhere an inner fn can return `{:nocache, {:ok, _}}` and an outer cache
  # (Sanbase.Cache, RehydratingCache, CachexProvider) wraps the call.
  #
  # Possible follow-up: replace opt-in tag preservation with a `Process.put` signal like
  # `SanbaseWeb.Graphql.CachexProvider` does. That avoids threading the opt through every
  # layer, but only works inside a request-scoped process, and `Sanbase.Cache` is used
  # outside request context too.
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
    # Inside ConCache.isolated/3, which locks the key first - covering another process
    # modifying it between the previous check and the lock.
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
    # An :ok tuple is cached; errors are not, and a :nocache tuple opts out manually.
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
