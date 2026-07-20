defmodule SanbaseWeb.Graphql.CachexProvider do
  @moduledoc """
  Cachex 4.x backed implementation of `SanbaseWeb.Graphql.CacheProvider`.

  Two hard-earned constraints shape this module (both caused production
  incidents when violated):

  1. The cache MUST be bounded. Cachex 4 removed the v3 `:limit`/`:policy`/
     `:reclaim` start options and silently ignores them, so passing them (as the
     first 4.x upgrade did) leaves the cache unbounded and OOM-kills the web
     pods. Neither built-in `Cachex.Limit.*` hook survives burst writes either —
     bound enforcement is done inline on the write path by
     `SanbaseWeb.Graphql.CachexBoundEnforcer` (see its moduledoc for details).
     A low-frequency `Cachex.Limit.Scheduled` hook remains as a backstop only.

  2. The `get_or_store/4` cache-miss function MUST run in the caller process.
     `Cachex.fetch/3` runs its fallback in a Courier-spawned worker, which
     breaks Absinthe Dataloader batching (`Dataloader.Ecto` batch keys embed
     the calling process pid) and loses process-dictionary signals like
     `:do_not_cache_query`. Stampede protection is instead done with per-key
     locks on Cachex's own Locksmith service via
     `SanbaseWeb.Graphql.CachexKeyLock` — no other caching library is involved.

  Full rationale, evidence and the testing guide: `docs/graphql-caching.md`.
  """
  @behaviour SanbaseWeb.Graphql.CacheProvider

  import Cachex.Spec

  alias SanbaseWeb.Graphql.CachexBoundEnforcer
  alias SanbaseWeb.Graphql.CachexKeyLock

  @default_max_entries 2_000_000
  @default_reclaim_ratio 0.3
  @default_ttl_seconds 300
  @default_expiration_interval_seconds 10

  # Values whose compressed size exceeds this are not cached. A handful of huge
  # results can dominate the memory bound that max_entries alone cannot express.
  @max_compressed_bytes 500_000

  # Lock losers poll the cache at this interval, waiting for the lock holder's
  # value to land; give up (raise) after the timeout.
  @lock_poll_interval_ms 50
  @lock_wait_timeout_ms 60_000

  @impl SanbaseWeb.Graphql.CacheProvider
  def start_link(opts) do
    Cachex.start_link(opts(opts))
  end

  @impl SanbaseWeb.Graphql.CacheProvider
  def child_spec(opts) do
    Supervisor.child_spec({Cachex, opts(opts)}, id: Keyword.fetch!(opts, :id))
  end

  defp opts(opts) do
    name = Keyword.fetch!(opts, :name)
    max_entries = Keyword.get(opts, :max_entries, @default_max_entries)
    reclaim = Keyword.get(opts, :reclaim, @default_reclaim_ratio)
    default_ttl = Keyword.get(opts, :default_ttl_seconds, @default_ttl_seconds)

    expiration_interval =
      Keyword.get(opts, :expiration_interval_seconds, @default_expiration_interval_seconds)

    CachexBoundEnforcer.register(name, max_entries, reclaim)

    [
      name: name,
      # Backstop pruning only — the main bound enforcement is done inline on
      # every write (see CachexBoundEnforcer), which survives write bursts that
      # overwhelm the hook-based Cachex.Limit.* implementations.
      hooks: [
        hook(
          module: Cachex.Limit.Scheduled,
          args: {max_entries, [reclaim: reclaim], [frequency: :timer.seconds(30)]}
        )
      ],
      expiration:
        expiration(
          default: :timer.seconds(default_ttl),
          interval: :timer.seconds(expiration_interval),
          lazy: true
        )
    ]
  end

  @impl SanbaseWeb.Graphql.CacheProvider
  def size(cache) do
    {:ok, bytes_size} = Cachex.inspect(cache, {:memory, :bytes})
    (bytes_size / (1024 * 1024)) |> Float.round(2)
  end

  @impl SanbaseWeb.Graphql.CacheProvider
  def count(cache) do
    {:ok, count} = Cachex.size(cache)
    count
  end

  @impl SanbaseWeb.Graphql.CacheProvider
  def clear_all(cache) do
    {:ok, _} = Cachex.clear(cache)
    :ok
  end

  @impl SanbaseWeb.Graphql.CacheProvider
  def get(cache, key) do
    case Cachex.get(cache, true_key(key)) do
      {:ok, compressed} when is_binary(compressed) -> decompress_value(compressed)
      _ -> nil
    end
  end

  @impl SanbaseWeb.Graphql.CacheProvider
  def store(cache, key, value) do
    case value do
      {:error, _} ->
        :ok

      {:nocache, _} ->
        Process.put(:do_not_cache_query, true)
        :ok

      _ ->
        put_compressed(cache, true_key(key), value, put_opts(key))
        :ok
    end
  end

  @impl SanbaseWeb.Graphql.CacheProvider
  def get_or_store(cache, key, func, cache_modify_middleware) do
    true_key = true_key(key)

    case Cachex.get(cache, true_key) do
      {:ok, compressed} when is_binary(compressed) ->
        decompress_value(compressed)

      _ ->
        get_or_execute_locked(cache, key, true_key, func, cache_modify_middleware, 0)
    end
  end

  # Per-key stampede protection via Cachex's Locksmith locks. The fallback runs
  # in the caller process so Absinthe's Dataloader batching and process-dict
  # signals (e.g. :do_not_cache_query) are preserved. Losers of the lock race
  # do NOT queue on the lock: they poll the cache (a cheap ETS read) and return
  # as soon as the winner's value lands, retrying the lock only if the winner
  # finished without caching anything (error/nocache results).
  defp get_or_execute_locked(cache, key, true_key, func, cache_modify_middleware, waited_ms) do
    locked_fun = fn ->
      # Re-check inside the lock: the previous holder may have cached the value
      case Cachex.get(cache, true_key) do
        {:ok, compressed} when is_binary(compressed) ->
          decompress_value(compressed)

        _ ->
          execute_and_maybe_cache(cache, key, true_key, func, cache_modify_middleware)
      end
    end

    case CachexKeyLock.try_with_lock(cache, true_key, locked_fun) do
      {:executed, result} ->
        result

      :locked ->
        if waited_ms >= @lock_wait_timeout_ms do
          raise "Timeout waiting for the cache lock for key #{inspect(true_key)}"
        end

        Process.sleep(@lock_poll_interval_ms)

        case Cachex.get(cache, true_key) do
          {:ok, compressed} when is_binary(compressed) ->
            decompress_value(compressed)

          _ ->
            get_or_execute_locked(
              cache,
              key,
              true_key,
              func,
              cache_modify_middleware,
              waited_ms + @lock_poll_interval_ms
            )
        end
    end
  end

  defp execute_and_maybe_cache(cache, key, true_key, func, cache_modify_middleware) do
    case safe_invoke(func) do
      {:ok, _} = ok_tuple ->
        put_compressed(cache, true_key, ok_tuple, put_opts(key))
        ok_tuple

      {:error, _} = error ->
        error

      {:nocache, value} ->
        Process.put(:do_not_cache_query, true)
        value

      {:middleware, _, _} = tuple ->
        cache_modify_middleware.(cache, key, tuple)
    end
  end

  # Match Cachex.fetch's behavior: a raise in the fallback fn becomes an
  # `{:error, message}` tuple so concurrent callers don't all crash. The
  # resolver layer treats errors as uncached.
  defp safe_invoke(func) do
    func.()
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp put_compressed(cache, true_key, value, put_opts) do
    compressed = compress_value(value)

    if byte_size(compressed) < @max_compressed_bytes and
         CachexBoundEnforcer.enforce(cache) != :over_hard_limit do
      Cachex.put(cache, true_key, compressed, put_opts)
      CachexBoundEnforcer.enforce(cache)
    end
  end

  defp put_opts({_key, ttl}) when is_integer(ttl), do: [expire: :timer.seconds(ttl)]
  defp put_opts(_key), do: []

  defp true_key({key, ttl}) when is_integer(ttl), do: key
  defp true_key(key), do: key

  defp compress_value(value) do
    value
    |> :erlang.term_to_binary()
    |> :zlib.gzip()
  end

  defp decompress_value(value) do
    value
    |> :zlib.gunzip()
    |> :erlang.binary_to_term()
  end
end
