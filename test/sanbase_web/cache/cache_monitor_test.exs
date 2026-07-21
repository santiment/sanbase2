defmodule SanbaseWeb.Graphql.CacheMonitorTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias SanbaseWeb.Graphql.CachexProvider
  alias SanbaseWeb.Graphql.CacheMonitor

  setup do
    cache = :"cache_monitor_test_#{System.unique_integer([:positive])}"
    {:ok, pid} = CachexProvider.start_link(name: cache, id: cache)
    on_exit(fn -> Process.exit(pid, :kill) end)

    %{cache: cache}
  end

  test "periodically logs entries, table memory and payload size", %{cache: cache} do
    CachexProvider.store(cache, "k1", {:ok, "some value"})
    CachexProvider.store(cache, "k2", {:ok, "another value"})

    log =
      capture_log(fn ->
        {:ok, pid} =
          CacheMonitor.start_link(
            name: :"#{cache}_monitor",
            cache: cache,
            interval: 50
          )

        Process.sleep(150)
        GenServer.stop(pid)
      end)

    assert log =~ "GraphQL cache stats: entries=2"
    assert log =~ "table_memory_mb="
    assert log =~ "payload_mb="
  end

  test "sweeps the oldest entries when the payload exceeds the bound", %{cache: cache} do
    # ~100kb of incompressible payload per entry, 20 entries => ~2MB total
    for i <- 1..20 do
      CachexProvider.store(cache, "k_#{i}", {:ok, :crypto.strong_rand_bytes(100_000)})
      # Distinct :modified timestamps so the LRW order is deterministic
      Process.sleep(2)
    end

    assert 20 == CachexProvider.count(cache)

    log =
      capture_log(fn ->
        {:ok, pid} =
          CacheMonitor.start_link(
            name: :"#{cache}_monitor",
            cache: cache,
            interval: 50,
            # 1MB bound, ~half of what is stored
            max_payload_mb: 1
          )

        Process.sleep(150)
        GenServer.stop(pid)
      end)

    assert log =~ "exceeded the"
    assert log =~ "swept the oldest entries"

    count = CachexProvider.count(cache)
    assert count < 20

    # The sweep is LRW: the newest entries must survive, the oldest must go
    assert nil == CachexProvider.get(cache, "k_1")
    assert {:ok, _} = CachexProvider.get(cache, "k_20")

    # Payload is back under the bound
    assert CachexProvider.payload_bytes(cache) <= 1024 * 1024
  end

  test "does not crash when the cache table does not exist" do
    log =
      capture_log(fn ->
        {:ok, pid} =
          CacheMonitor.start_link(
            name: :cache_monitor_missing_test,
            cache: :nonexistent_cache_table,
            interval: 50
          )

        Process.sleep(150)
        GenServer.stop(pid)
      end)

    refute log =~ "GraphQL cache stats"
  end
end
