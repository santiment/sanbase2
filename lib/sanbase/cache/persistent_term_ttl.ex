defmodule Sanbase.Cache.PersistentTermTtl do
  @moduledoc """
  Read-through `:persistent_term` cache with a TTL.

  Entries are `{value, expires_at}` (monotonic milliseconds). Reads are
  lock-free and copy-free; an expired entry is rebuilt lazily by the
  reader. Writes trigger a global GC scan, so this fits data read
  constantly and rebuilt rarely. Concurrent rebuild races are harmless —
  last write wins with an equally fresh value.

  Namespace keys with the owning module, e.g. `{MyModule, :some_cache}`.
  """

  @type key() :: term()
  @type ttl_ms() :: pos_integer()
  @type rebuild_fun() :: (-> {:store, term()} | {:nostore, term()})

  @doc """
  The cached value for `key`, rebuilt with `fun` when missing or past
  its TTL.

  `fun` returns `{:store, value}` to cache `value` for `ttl_ms`, or
  `{:nostore, value}` to return it uncached (e.g. a fallback that should
  be retried on the next read).
  """
  @spec get_or_store(key(), ttl_ms(), rebuild_fun()) :: term()
  def get_or_store(key, ttl_ms, fun) when is_function(fun, 0) do
    now = System.monotonic_time(:millisecond)

    case :persistent_term.get(key, nil) do
      {value, expires_at} when expires_at > now -> value
      _ -> store(key, ttl_ms, fun)
    end
  end

  @doc """
  Rebuild the entry unconditionally, resetting its TTL. Same `fun`
  contract as `get_or_store/3`. Returns the value.
  """
  @spec store(key(), ttl_ms(), rebuild_fun()) :: term()
  def store(key, ttl_ms, fun) when is_function(fun, 0) do
    case fun.() do
      {:store, value} ->
        :persistent_term.put(key, {value, System.monotonic_time(:millisecond) + ttl_ms})
        value

      {:nostore, value} ->
        value
    end
  end

  @doc """
  The cached value ignoring the TTL, or `:error` when nothing is stored.
  For serving stale data when a rebuild fails.
  """
  @spec get_stale(key()) :: {:ok, term()} | :error
  def get_stale(key) do
    case :persistent_term.get(key, nil) do
      {value, _expires_at} -> {:ok, value}
      nil -> :error
    end
  end

  @doc """
  Expire the entry so the next read rebuilds it. No-op when nothing is
  stored.
  """
  @spec expire(key()) :: :ok
  def expire(key) do
    case :persistent_term.get(key, nil) do
      {value, _expires_at} ->
        :persistent_term.put(key, {value, System.monotonic_time(:millisecond) - 1})
        :ok

      nil ->
        :ok
    end
  end

  @doc """
  Remove the entry.
  """
  @spec erase(key()) :: :ok
  def erase(key) do
    :persistent_term.erase(key)
    :ok
  end
end
