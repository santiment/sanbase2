defmodule SanbaseWeb.Graphql.CachexKeyLock do
  @moduledoc """
  Per-key mutual exclusion built on Cachex's own Locksmith service.

  `try_with_lock/3` runs the given function in the **calling process** while
  holding a per-key lock — the property the GraphQL cache needs for its
  cache-miss functions. `Dataloader.Ecto` embeds `self()` into every batch
  key (the pid is later passed to Ecto as the `:caller` option for connection
  ownership), so `Dataloader.load` and `Dataloader.get` must both run in the
  Absinthe resolution process — executed anywhere else, batch lookups miss
  and dataloader-backed fields resolve to `nil` or crash. Process-dictionary
  signals like `:do_not_cache_query` are process-scoped too. See
  `docs/graphql-caching.md` for the full analysis and reproduction.

  Neither public Cachex primitive provides caller-process execution:

    * `Cachex.fetch/3` runs its fallback in a Courier-spawned worker process
      (and shares in-flight results — including per-request middleware
      tuples — across concurrent callers of the same key);
    * `Cachex.transaction/3` runs its function in the cache's single locksmith
      queue process, serializing all transactions cache-wide.

  So this module drives `Cachex.Services.Locksmith.lock/2` / `unlock/2`
  directly (plain ETS `insert_new`/`delete` calls), the same approach the
  Cachex v3 provider used for years. Acquisition is non-blocking: when the key
  is already locked, `:locked` is returned and the caller decides how to wait
  (the provider polls the cache itself, so waiters return as soon as the
  computed value lands without ever taking the lock).

  Locksmith locks are not monitored by Cachex: a process that dies brutally
  (e.g. the request process killed on client disconnect) while holding a lock
  would leak it. Every lock therefore gets a tiny guard process that monitors
  the owner and releases the lock on `:DOWN` with an owner-matched
  `:ets.delete_object/2` — precise even if the key has since been re-locked
  by someone else.
  """

  import Cachex.Spec

  alias Cachex.Services.Locksmith

  # Cachex's global lock table, defined in Cachex.Services.Locksmith. Referenced
  # directly only for the owner-matched cleanup delete in the release guard;
  # every other operation goes through the Locksmith module.
  @locksmith_table :cachex_locksmith

  @doc """
  Attempts to take an exclusive lock on `key` and run `fun` in the calling
  process.

  Returns `{:executed, result}` when the lock was acquired (released again
  before returning), or `:locked` without blocking when another process holds
  the lock.
  """
  @spec try_with_lock(atom(), term(), (-> result)) :: {:executed, result} | :locked
        when result: term()
  def try_with_lock(cache, key, fun) when is_function(fun, 0) do
    {:ok, cache_record} = Cachex.inspect(cache, :cache)

    case Locksmith.lock(cache_record, [key]) do
      false ->
        :locked

      true ->
        guard = start_release_guard(cache_record, key, self())

        try do
          {:executed, fun.()}
        after
          Locksmith.unlock(cache_record, [key])
          send(guard, :done)
        end
    end
  end

  # Releases the lock if the owner dies without reaching its `after` block
  # (brutal kills skip `after`). The delete matches both key AND owner pid, so
  # a lock legitimately re-acquired by another process is never touched.
  defp start_release_guard(cache_record, key, owner) do
    cache(name: cache_name) = cache_record

    spawn(fn ->
      ref = Process.monitor(owner)

      receive do
        :done ->
          :ok

        {:DOWN, ^ref, :process, ^owner, _reason} ->
          :ets.delete_object(@locksmith_table, {{cache_name, key}, owner})
      end
    end)
  end
end
