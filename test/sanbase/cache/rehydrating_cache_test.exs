defmodule Sanbase.Cache.RehydratingCacheTest do
  # `Sanbase.Cache.RehydratingCache` registers itself under a fixed name
  # (`:__rehydrating_cache__`), and its store/task supervisor are similarly
  # fixed-named. Two instances cannot coexist, so this file runs serially.
  use ExUnit.Case, async: false

  alias Sanbase.Cache.RehydratingCache

  setup context do
    # Fresh supervisor per test. No manual `stop_supervised` needed: ExUnit tracks
    # everything started via `start_supervised!/1` under a test-owned supervisor
    # and shuts them down in reverse start order when the test exits (pass, fail,
    # or crash). That tears down the RC GenServer, its ConCache store, and the
    # Task.Supervisor — so no state (or in-progress task child) survives into the
    # next test.
    #
    # Tests tune timing/limits via tags (e.g. `@tag run_interval: 20`,
    # `@tag unused_key_pause_seconds: 0`); anything untagged uses the production
    # defaults baked into the module.
    opts =
      context
      |> Map.take([
        :run_interval,
        :unused_key_pause_seconds,
        :unused_key_drop_seconds,
        :max_spawns_per_run
      ])
      |> Enum.to_list()

    start_supervised!({Sanbase.Cache.RehydratingCache.Supervisor, opts})
    :ok
  end

  describe "register_function/5 + get/2" do
    test "happy path: registered function result is returned" do
      key = {:rc_test, :happy_path}
      :ok = RehydratingCache.register_function(fn -> {:ok, 42} end, key, 60, 30)

      assert {:ok, 42} = RehydratingCache.get(key, 2_000)
    end

    test "returns :not_registered when key is missing" do
      assert {:error, :not_registered} =
               RehydratingCache.get({:rc_test, :missing}, 500)
    end

    test "duplicate registration returns {:error, :already_registered}" do
      key = {:rc_test, :dup}
      :ok = RehydratingCache.register_function(fn -> {:ok, 1} end, key, 60, 30)

      assert {:error, :already_registered} =
               RehydratingCache.register_function(fn -> {:ok, 2} end, key, 60, 30)
    end
  end

  describe "refresh" do
    test "re-evaluates the function after refresh_time_delta when :run fires" do
      key = {:rc_test, :refresh}
      counter = :counters.new(1, [])

      fun = fn ->
        :ok = :counters.add(counter, 1, 1)
        {:ok, :counters.get(counter, 1)}
      end

      # refresh_time_delta = 1s (smallest allowed by the guard `delta < ttl`)
      :ok = RehydratingCache.register_function(fun, key, 60, 1)

      assert {:ok, 1} = RehydratingCache.get(key, 2_000)

      # Wait past refresh_time_delta, then manually trigger a :run tick so the
      # test does not depend on the 20s internal interval.
      Process.sleep(1_100)
      send(RehydratingCache.name(), :run)

      # Spin until the store reflects the refreshed value (caps at ~2s).
      assert eventually(fn -> RehydratingCache.get(key, 100) == {:ok, 2} end)
    end
  end

  describe "failure handling" do
    @tag capture_log: true
    test "task crash transitions progress to :failed and the function reruns on next :run" do
      key = {:rc_test, :fail_then_succeed}
      # Flip after the first crash so the retry succeeds.
      agent = start_supervised!({Agent, fn -> :crash end})

      fun = fn ->
        case Agent.get_and_update(agent, fn
               :crash -> {:crash, :ok}
               :ok -> {:ok, :ok}
             end) do
          :crash -> raise "boom"
          :ok -> {:ok, :recovered}
        end
      end

      :ok = RehydratingCache.register_function(fun, key, 60, 30)

      # First attempt dies. The waiting caller is freed with an error — either
      # the crash reply (if it was already parked) or a plain timeout (if it
      # arrived after the crash was recorded). Both are acceptable here.
      assert {:error, _} = RehydratingCache.get(key, 300)

      # Trigger a manual :run so the retry fires without waiting for the 20s tick.
      send(RehydratingCache.name(), :run)

      assert eventually(fn ->
               RehydratingCache.get(key, 200) == {:ok, :recovered}
             end)
    end
  end

  describe "concurrent get while computation is in progress" do
    test "multiple callers are served the same result" do
      key = {:rc_test, :concurrent}
      parent = self()

      fun = fn ->
        # Signal that the task started, then sleep so both gets land in the
        # waiting list before the result is produced.
        send(parent, :task_started)
        Process.sleep(200)
        {:ok, :shared_value}
      end

      :ok = RehydratingCache.register_function(fun, key, 60, 30)
      assert_receive :task_started, 1_000

      t1 = Task.async(fn -> RehydratingCache.get(key, 2_000) end)
      t2 = Task.async(fn -> RehydratingCache.get(key, 2_000) end)

      assert Task.await(t1, 3_000) == {:ok, :shared_value}
      assert Task.await(t2, 3_000) == {:ok, :shared_value}
    end
  end

  describe "waiting-list timeout" do
    test "get/2 returns {:error, :timeout} when the task stalls past the caller timeout" do
      key = {:rc_test, :stalled}

      fun = fn ->
        Process.sleep(:infinity)
      end

      :ok = RehydratingCache.register_function(fun, key, 60, 30)

      assert {:error, :timeout} = RehydratingCache.get(key, 150)
    end
  end

  describe ":nocache passthrough" do
    test "{:nocache, {:ok, value}} is exposed when return_nocache: true" do
      key = {:rc_test, :nocache}
      :ok = RehydratingCache.register_function(fn -> {:nocache, {:ok, :fresh}} end, key, 60, 30)

      assert {:nocache, {:ok, :fresh}} =
               RehydratingCache.get(key, 2_000, return_nocache: true)
    end

    test "{:nocache, {:ok, value}} collapses to {:ok, value} by default" do
      key = {:rc_test, :nocache_default}
      :ok = RehydratingCache.register_function(fn -> {:nocache, {:ok, :fresh}} end, key, 60, 30)

      assert {:ok, :fresh} = RehydratingCache.get(key, 2_000)
    end
  end

  describe "no duplicate spawns" do
    @tag run_interval: 20
    test "a slow function is not re-spawned while it is still in progress" do
      # Register several functions whose in-progress markers used to be dropped
      # by the do_run accumulator bug, causing a fresh task to be spawned on
      # every tick while the previous one was still running. With a small run
      # interval, many ticks fire during each function's sleep; each function
      # must still start exactly once.
      keys = for i <- 1..3, do: {:rc_test, :no_dup, i}
      counters = Map.new(keys, fn key -> {key, :counters.new(1, [])} end)

      Enum.each(keys, fn key ->
        counter = counters[key]

        fun = fn ->
          :ok = :counters.add(counter, 1, 1)
          Process.sleep(200)
          {:ok, key}
        end

        # Large refresh_time_delta so no legitimate refresh happens during the test.
        :ok = RehydratingCache.register_function(fun, key, 300, 250)
      end)

      # ~40 ticks worth of time. Under the bug each key would be spawned dozens
      # of times; with the fix each is spawned exactly once.
      Process.sleep(800)

      Enum.each(keys, fn key ->
        assert :counters.get(counters[key], 1) == 1
      end)
    end
  end

  describe "error result delivery" do
    test "an error result is delivered to a waiting caller promptly" do
      key = {:rc_test, :error_reply}

      fun = fn ->
        Process.sleep(100)
        {:error, :boom}
      end

      :ok = RehydratingCache.register_function(fun, key, 60, 30)

      # Before the fix this blocked until the caller's own timeout (returning
      # {:error, :timeout}); now the error is forwarded as soon as it is produced.
      assert {:error, :boom} = RehydratingCache.get(key, 2_000)
    end
  end

  describe "retry backoff" do
    @tag run_interval: 20
    test "a persistently :nocache function is not re-run on every tick" do
      key = {:rc_test, :backoff}
      counter = :counters.new(1, [])

      fun = fn ->
        :ok = :counters.add(counter, 1, 1)
        {:nocache, {:ok, :partial}}
      end

      # Small refresh_time_delta caps the backoff; ttl keeps the value around.
      :ok = RehydratingCache.register_function(fun, key, 60, 5)

      # Many ticks fire in this window. Without backoff the fun would run on
      # every tick (dozens of times); with exponential backoff (1s, 2s, 4s, ...
      # capped at refresh_time_delta) it runs only a handful of times.
      Process.sleep(1_500)

      runs = :counters.get(counter, 1)
      assert runs >= 2, "expected the function to retry at least a couple of times, got #{runs}"
      assert runs <= 15, "expected backoff to throttle retries, but ran #{runs} times"
    end
  end

  describe "unused key lifecycle" do
    @tag run_interval: 20
    @tag unused_key_pause_seconds: 0
    test "stops refreshing a key that is no longer read" do
      key = {:rc_test, :pause_unused}
      counter = :counters.new(1, [])

      fun = fn ->
        :ok = :counters.add(counter, 1, 1)
        {:ok, :ran}
      end

      # Refresh every 1s, but the key counts as unused the moment it is not read.
      # It runs once at registration and, since the test never reads it again,
      # never refreshes.
      :ok = RehydratingCache.register_function(fun, key, 60, 1)

      Process.sleep(2_000)

      assert :counters.get(counter, 1) == 1
    end

    @tag run_interval: 20
    @tag unused_key_drop_seconds: 0
    test "forgets a key that has been unread past the drop threshold" do
      key = {:rc_test, :drop_unused}
      :ok = RehydratingCache.register_function(fn -> {:ok, :v} end, key, 60, 30)

      # Give the run loop time to observe the key as unread and drop it.
      Process.sleep(800)

      # Remove the stored value so the read cannot be served from the store; the
      # closure was forgotten, so the key is unregistered again.
      Sanbase.Cache.clear(Sanbase.Cache.RehydratingCache.Store.name(), key)

      assert {:error, :not_registered} = RehydratingCache.get(key, 300)
    end
  end

  describe "spawn cap" do
    # Large run interval so ticks only fire when the test sends them manually.
    @tag run_interval: 3_600_000
    @tag max_spawns_per_run: 3
    test "caps the number of tasks started in a single run tick" do
      starts = :counters.new(1, [])
      keys = for i <- 1..6, do: {:rc_test, :cap, i}

      Enum.each(keys, fn key ->
        fun = fn ->
          :ok = :counters.add(starts, 1, 1)
          {:ok, :v}
        end

        # refresh_time_delta = 1 so every key becomes due ~1s after registration.
        :ok = RehydratingCache.register_function(fun, key, 60, 1)
      end)

      # Each function runs once on registration.
      assert eventually(fn -> :counters.get(starts, 1) == 6 end)

      # Let all six keys come due, then drive exactly one run tick.
      Process.sleep(1_100)
      send(RehydratingCache.name(), :run)
      Process.sleep(300)

      # Only max_spawns_per_run (3) additional tasks may start in that tick.
      assert :counters.get(starts, 1) == 9
    end
  end

  # --- helpers ---

  defp eventually(fun, attempts \\ 40, interval_ms \\ 50) do
    Enum.reduce_while(1..attempts, false, fn _, _acc ->
      if fun.() do
        {:halt, true}
      else
        Process.sleep(interval_ms)
        {:cont, false}
      end
    end)
  end
end
