defmodule Sanbase.Cache.PersistentTermTtlTest do
  # Keys are unique per test, so tests don't interfere despite
  # :persistent_term being VM-global.
  use ExUnit.Case, async: true

  alias Sanbase.Cache.PersistentTermTtl, as: Cache

  @ttl_ms :timer.minutes(1)

  setup context do
    key = {__MODULE__, context.test}
    on_exit(fn -> Cache.erase(key) end)
    {:ok, key: key}
  end

  defp counting_rebuild(result) do
    test_pid = self()

    fn ->
      send(test_pid, :rebuilt)
      result
    end
  end

  test "get_or_store/3 rebuilds once and serves the cached value", %{key: key} do
    rebuild = counting_rebuild({:store, :value})

    assert Cache.get_or_store(key, @ttl_ms, rebuild) == :value
    assert Cache.get_or_store(key, @ttl_ms, rebuild) == :value

    assert_received :rebuilt
    refute_received :rebuilt
  end

  test "a {:nostore, value} rebuild is returned but not cached", %{key: key} do
    rebuild = counting_rebuild({:nostore, :fallback})

    assert Cache.get_or_store(key, @ttl_ms, rebuild) == :fallback
    assert Cache.get_or_store(key, @ttl_ms, rebuild) == :fallback

    # Rebuilt on every read since nothing was stored.
    assert_received :rebuilt
    assert_received :rebuilt
  end

  test "expire/1 forces the next read to rebuild", %{key: key} do
    assert Cache.get_or_store(key, @ttl_ms, fn -> {:store, :old} end) == :old

    Cache.expire(key)

    assert Cache.get_or_store(key, @ttl_ms, fn -> {:store, :new} end) == :new
  end

  test "expire/1 on a missing entry is a no-op", %{key: key} do
    assert Cache.expire(key) == :ok
  end

  test "store/3 replaces the value unconditionally", %{key: key} do
    assert Cache.get_or_store(key, @ttl_ms, fn -> {:store, :old} end) == :old
    assert Cache.store(key, @ttl_ms, fn -> {:store, :new} end) == :new
    assert Cache.get_or_store(key, @ttl_ms, fn -> {:store, :unused} end) == :new
  end

  test "get_stale/1 serves the value even past the TTL", %{key: key} do
    assert Cache.get_stale(key) == :error

    Cache.get_or_store(key, @ttl_ms, fn -> {:store, :value} end)
    Cache.expire(key)

    assert Cache.get_stale(key) == {:ok, :value}
  end

  test "erase/1 removes the entry", %{key: key} do
    Cache.get_or_store(key, @ttl_ms, fn -> {:store, :value} end)
    Cache.erase(key)

    assert Cache.get_stale(key) == :error
  end
end
