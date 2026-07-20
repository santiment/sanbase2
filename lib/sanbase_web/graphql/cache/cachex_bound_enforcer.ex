defmodule SanbaseWeb.Graphql.CachexBoundEnforcer do
  @moduledoc """
  Hard entry-count bound enforcement for Cachex caches.

  Cachex 4 removed the v3 `:limit`/`:policy`/`:reclaim` start options (they are
  silently ignored) and replaced them with the `Cachex.Limit.Scheduled` and
  `Cachex.Limit.Evented` hooks. Neither gives a hard bound under write bursts:

    * `Scheduled` is timer-only — overshoot is `write_rate × frequency`,
      unbounded in principle.
    * `Evented` funnels every write through a single hook GenServer that
      prunes per message; when writes outpace pruning it falls far behind
      (the bench in `load_test/scripts/cachex_provider_bench.exs` measured
      ~8× the configured limit).

  This module enforces the bound inline on the write path instead:

    * `register/3` stores the bound and a single-flight prune flag in
      `:persistent_term` at cache start.
    * `enforce/1` is called by the cache owner around writes. It reads the ETS
      size (cheap `:ets.info/2`), and when the bound is exceeded exactly one
      process — the one that flips the `:atomics` flag 0 -> 1 — spawns an async
      `Cachex.prune/3` while the rest carry on.
    * A single pruner cannot outrun a write burst (pruning sorts the table,
      writes don't), so past a hard ceiling `enforce/1` returns
      `:over_hard_limit` and callers are expected to shed the write — dropping
      a write is always correct for a cache and keeps the memory bound hard.
  """

  # Writes should be shed once the cache exceeds max_entries by this ratio —
  # the point where the async pruner has demonstrably fallen behind a burst.
  @hard_limit_ratio 1.1

  @type enforce_result :: :ok | :over_soft_limit | :over_hard_limit

  @doc """
  Registers the bound for a cache: max entries, reclaim ratio and a
  single-flight prune flag. Call once at cache start; entries live in
  `:persistent_term`, so this must not be called repeatedly with a fresh
  cache name per call site.
  """
  @spec register(atom(), pos_integer(), float()) :: :ok
  def register(cache, max_entries, reclaim) do
    :persistent_term.put(
      {__MODULE__, cache},
      %{max_entries: max_entries, reclaim: reclaim, prune_flag: :atomics.new(1, [])}
    )
  end

  @doc """
  Enforces the registered bound on a cache.

  Returns `:ok` when under the bound (or when no bound is registered),
  `:over_soft_limit` when over the bound (an async prune has been triggered)
  and `:over_hard_limit` when over `#{@hard_limit_ratio} × max_entries` — the
  caller should shed the write in that case.
  """
  @spec enforce(atom()) :: enforce_result()
  def enforce(cache) do
    case :persistent_term.get({__MODULE__, cache}, nil) do
      %{max_entries: max_entries, reclaim: reclaim, prune_flag: prune_flag} ->
        case :ets.info(cache, :size) do
          entries when is_integer(entries) and entries > max_entries ->
            maybe_spawn_pruner(cache, max_entries, reclaim, prune_flag)

            if entries > trunc(max_entries * @hard_limit_ratio) do
              :over_hard_limit
            else
              :over_soft_limit
            end

          _ ->
            :ok
        end

      nil ->
        # Cache started without register/3 — no bound to enforce.
        :ok
    end
  end

  defp maybe_spawn_pruner(cache, max_entries, reclaim, prune_flag) do
    case :atomics.compare_exchange(prune_flag, 1, 0, 1) do
      :ok ->
        spawn(fn ->
          try do
            Cachex.prune(cache, max_entries, reclaim: reclaim)
          rescue
            # The cache can be stopping while a prune is in flight; there is
            # nothing to enforce in that case.
            _ -> :ok
          after
            :atomics.put(prune_flag, 1, 0)
          end

          # Writes that landed while pruning may have pushed the size over the
          # bound again with no further writes coming to re-trigger enforcement.
          enforce(cache)
        end)

      _already_pruning ->
        :ok
    end
  end
end
