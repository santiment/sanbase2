defmodule Sanbase.Cache.PersistentTermTtl do
  @moduledoc """
  Read-through `:persistent_term` cache with a TTL.

  Entries are stored as `{value, expires_at}` (monotonic milliseconds)
  under the caller-supplied key. Reads are lock-free and copy-free; an
  expired entry is rebuilt lazily by the reading process. Writes trigger
  a global GC scan (the `:persistent_term` trade-off), so this fits data
  that is read constantly and rebuilt rarely — once per TTL, or eagerly
  via `store/3`.

  Namespace keys with the owning module, e.g. `{MyModule, :some_cache}`.

  Concurrent readers hitting an expired entry may race several rebuilds;
  each stores an equally fresh value, so last-write-wins is harmless.

  The same hand-rolled pattern predates this module in
  `Sanbase.Accounts.ProtectedUser`,
  `Sanbase.ExternalServices.Coinmarketcap.Utils` and
  `Sanbase.Clickhouse.MetricAdapter`; migrate them here over time.
  """

  @type key() :: term()
  @type ttl_ms() :: pos_integer()
  @type rebuild_fun() :: (-> {:store, term()} | {:nostore, term()})

  @doc """
  The cached value for `key`, rebuilt with `fun` when the entry is
  missing or past its TTL.

  `fun` must return `{:store, value}` to cache `value` for `ttl_ms`, or
  `{:nostore, value}` to return `value` without caching it — e.g. a
  fallback computed during an outage, so the rebuild is retried on the
  next read instead of being cached for a full TTL.
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
  Rebuild the entry with `fun` unconditionally, resetting its TTL. Same
  `fun` contract as `get_or_store/3`. Returns the value.
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
  The cached value for `key` ignoring the TTL, or `:error` when nothing
  is stored. For keep-serving-stale-data-on-rebuild-failure policies.
  """
  @spec get_stale(key()) :: {:ok, term()} | :error
  def get_stale(key) do
    case :persistent_term.get(key, nil) do
      {value, _expires_at} -> {:ok, value}
      nil -> :error
    end
  end

  @doc """
  Back-date the entry past its TTL so the next read rebuilds it. No-op
  when nothing is stored. For tests and ops.
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
  Remove the entry entirely.
  """
  @spec erase(key()) :: :ok
  def erase(key) do
    :persistent_term.erase(key)
    :ok
  end
end
