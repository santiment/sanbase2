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

  require Logger

  alias SanbaseWeb.Graphql.CachexBoundEnforcer
  alias SanbaseWeb.Graphql.CachexKeyLock

  @default_max_entries 50_000
  @default_reclaim_ratio 0.3
  @default_ttl_seconds 300
  @default_expiration_interval_seconds 10

  # Values whose compressed size exceeds this are not cached. A handful of huge
  # results can dominate the memory bound that max_entries alone cannot express.
  @max_compressed_bytes 500_000

  # The byte-size bound of the whole cache, enforced periodically by
  # SanbaseWeb.Graphql.CacheMonitor
  @max_payload_mb 1024

  @doc "The byte-size bound of the cache payload, in megabytes."
  @spec max_payload_mb() :: pos_integer()
  def max_payload_mb(), do: @max_payload_mb

  # Lock losers poll for the holder's value with backoff; on timeout they
  # recompute instead of erroring (see lock_or_poll/5). The wait must outlast
  # the ClickHouse budget bounding the holder. See docs/timeouts.md.
  @lock_poll_initial_ms 10
  @lock_poll_max_ms 100
  @lock_wait_timeout_ms 102_000

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
    case lookup(cache, true_key(key)) do
      {:hit, value} -> value
      :miss -> nil
    end
  end

  @doc """
  The total byte size of the compressed values stored in the cache.

  Unlike `size/1` (the ETS table memory, which counts only per-entry overhead
  because the gzipped values are refc binaries stored off-table), this walks
  the whole table — O(n), ~40ms per 200k entries. Meant for periodic
  monitoring, never for hot paths.

  A maintained O(1) counter is not possible: puts could increment it, but the
  Cachex janitor removes expired entries with `:ets.select_delete/2` — a
  native batch delete where the removed entries never surface in Elixir, so
  there is nothing to decrement from.
  """
  @spec payload_bytes(atom()) :: non_neg_integer()
  def payload_bytes(cache) do
    query = Cachex.Query.build(output: :value)
    {:ok, stream} = Cachex.stream(cache, query)

    Enum.reduce(stream, 0, fn
      value, acc when is_binary(value) -> acc + byte_size(value)
      _value, acc -> acc
    end)
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

    # The function runs in the caller process (see moduledoc), guarded by a
    # per-key lock. Lock losers do not queue: they poll the cache and return
    # as soon as the winner's value lands, retrying the lock only if the
    # winner cached nothing (error/nocache results).
    try_with_lock = fn ->
      CachexKeyLock.try_with_lock(cache, true_key, fn ->
        # Re-check inside the lock: a previous holder may have cached the value
        case lookup(cache, true_key) do
          {:hit, value} -> value
          :miss -> execute_and_maybe_cache(cache, key, true_key, func, cache_modify_middleware)
        end
      end)
    end

    execute_unlocked = fn ->
      execute_and_maybe_cache(cache, key, true_key, func, cache_modify_middleware)
    end

    case lookup(cache, true_key) do
      {:hit, value} ->
        value

      :miss ->
        lock_or_poll(cache, true_key, try_with_lock, execute_unlocked, 0, @lock_poll_initial_ms)
    end
  end

  defp lock_or_poll(cache, true_key, try_with_lock, execute_unlocked, waited_ms, interval_ms) do
    case try_with_lock.() do
      {:executed, result} ->
        result

      :locked when waited_ms >= @lock_wait_timeout_ms ->
        # The holder outlasted a whole CH query budget, so it's anomalous.
        # Recompute rather than raise (the old provider raised here — top
        # Sentry error for years). Web callers are usually cut off before this
        # lands; it's a best-effort net, correct for MCP/background callers.
        # See docs/timeouts.md.
        Logger.warning(
          "Cache lock for key #{inspect(true_key)} held longer than " <>
            "#{@lock_wait_timeout_ms}ms — computing without the lock"
        )

        execute_unlocked.()

      :locked ->
        Process.sleep(interval_ms)

        case lookup(cache, true_key) do
          {:hit, value} ->
            value

          :miss ->
            lock_or_poll(
              cache,
              true_key,
              try_with_lock,
              execute_unlocked,
              waited_ms + interval_ms,
              min(interval_ms * 2, @lock_poll_max_ms)
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
      # Both enforce calls are needed: the one above sheds writes when far
      # over the bound, this one triggers pruning if this write crossed it
      CachexBoundEnforcer.enforce(cache)
    end
  end

  # All cached values are compressed binaries; anything else is a miss.
  defp lookup(cache, true_key) do
    case Cachex.get(cache, true_key) do
      {:ok, compressed} when is_binary(compressed) -> {:hit, decompress_value(compressed)}
      _ -> :miss
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
