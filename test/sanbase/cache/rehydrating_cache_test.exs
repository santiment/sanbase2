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
    # `@tag unused_key_pause_ms: 0`); anything untagged uses the production
    # defaults baked into the module.
    opts =
      context
      |> Map.take([
        :run_interval,
        :function_runtime_timeout,
        :unused_key_pause_ms,
        :unused_key_drop_ms,
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

  describe "retry cadence" do
    @tag run_interval: 20
    test "a persistently :nocache function is re-run on every tick" do
      key = {:rc_test, :nocache_every_tick}
      counter = :counters.new(1, [])

      fun = fn ->
        :ok = :counters.add(counter, 1, 1)
        {:nocache, {:ok, :partial}}
      end

      :ok = RehydratingCache.register_function(fun, key, 60, 30)

      # :nocache means "retry on the next tick" with no backoff, so with a 20ms
      # run interval the fun reruns dozens of times in this window. The stored
      # partial keeps being served meanwhile.
      Process.sleep(1_500)

      runs = :counters.get(counter, 1)
      assert runs >= 10, "expected :nocache to retry on every tick, got only #{runs} runs"
      assert {:nocache, {:ok, :partial}} = RehydratingCache.get(key, 200, return_nocache: true)
    end

    @tag run_interval: 20
    @tag capture_log: true
    test "a persistently failing function is retried with backoff" do
      key = {:rc_test, :error_backoff}
      counter = :counters.new(1, [])

      fun = fn ->
        :ok = :counters.add(counter, 1, 1)
        {:error, :boom}
      end

      # Small refresh_time_delta caps the backoff; without backoff the fun would
      # run on every 20ms tick (dozens of times). With backoff (1s, 2s, 4s, ...
      # capped at refresh_time_delta = 5s) only a handful of runs fit here.
      :ok = RehydratingCache.register_function(fun, key, 60, 5)

      Process.sleep(1_500)

      runs = :counters.get(counter, 1)
      assert runs >= 2, "expected the function to retry at least a couple of times, got #{runs}"
      assert runs <= 15, "expected backoff to throttle retries, but ran #{runs} times"
    end

    @tag run_interval: 20
    @tag capture_log: true
    test "a :nocache result resets the error backoff" do
      key = {:rc_test, :backoff_reset}
      # Runs: 1st -> error, 2nd -> error, 3rd -> nocache (resets), 4th+ -> error.
      run_times = start_supervised!({Agent, fn -> [] end})

      fun = fn ->
        Agent.update(run_times, &[System.monotonic_time(:millisecond) | &1])
        n = Agent.get(run_times, &length/1)

        case n do
          3 -> {:nocache, {:ok, :partial}}
          _ -> {:error, :boom}
        end
      end

      # refresh_time_delta = 60 so the backoff cap does not mask growth: without
      # the reset the delay after run 3 would be 4s (fail count 3), with the
      # reset it is ~0s (nocache -> next tick) and run 4's own delay is 1s again.
      :ok = RehydratingCache.register_function(fun, key, 120, 60)

      # Wait for 5 runs: 0s, +1s, +2s, +~0s (nocache), +1s => ~4-5s in total.
      assert eventually(fn -> Agent.get(run_times, &length/1) >= 5 end, 80, 100)

      [t5, t4, t3, _t2, _t1] = Agent.get(run_times, &Enum.take(&1, 5))

      # Run 4 fires on the tick right after the :nocache run 3 (second
      # granularity allows up to ~1s); without the reset it would be ~4s later.
      assert t4 - t3 < 2_500, "expected next-tick rerun after :nocache, waited #{t4 - t3}ms"
      # Run 5 comes after run 4's error with a RESET backoff (~1s, not ~4s+).
      assert t5 - t4 < 2_500, "expected reset backoff after :nocache, waited #{t5 - t4}ms"
    end
  end

  describe "unused key lifecycle" do
    @tag run_interval: 20
    @tag unused_key_pause_ms: 0
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
    @tag unused_key_pause_ms: 0
    test "a read resumes a paused key and it recomputes promptly" do
      key = {:rc_test, :resume_paused}
      counter = :counters.new(1, [])

      fun = fn ->
        :ok = :counters.add(counter, 1, 1)
        {:ok, :counters.get(counter, 1)}
      end

      :ok = RehydratingCache.register_function(fun, key, 60, 1)

      # Runs once at registration, then pauses (unread past the 0ms threshold).
      Process.sleep(2_000)
      assert :counters.get(counter, 1) == 1

      # A read serves the stored value AND resumes the key as immediately due,
      # so the recompute happens on the next tick rather than after a whole
      # refresh window.
      assert {:ok, 1} = RehydratingCache.get(key, 200)
      assert eventually(fn -> :counters.get(counter, 1) >= 2 end)
    end

    @tag run_interval: 20
    @tag unused_key_drop_ms: 0
    test "forgets a key that has been unread past the drop threshold" do
      key = {:rc_test, :drop_unused}
      # ttl 60 so the stored value would long outlive the drop if it were not
      # evicted - the read below must miss because of the drop, not a TTL lapse.
      :ok = RehydratingCache.register_function(fn -> {:ok, :v} end, key, 60, 30)

      # Give the run loop time to observe the key as unread and drop it. Sleep
      # past a full second: last_access is second-granularity, so with a 0ms drop
      # threshold the key only becomes droppable once the wall clock has advanced
      # at least one second beyond registration.
      Process.sleep(1_500)

      # Dropping evicts the stored value too, so the read cannot be served from
      # the store and falls through to :not_registered.
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

    # Large run interval so ticks only fire manually; 0 runtime timeout makes
    # every in-progress task look "stuck" so restarts go through the cap.
    @tag run_interval: 3_600_000
    @tag function_runtime_timeout: 0
    @tag max_spawns_per_run: 3
    test "restarts of stuck tasks respect the spawn cap" do
      starts = :counters.new(1, [])
      keys = for i <- 1..6, do: {:rc_test, :stuck_cap, i}

      Enum.each(keys, fn key ->
        fun = fn ->
          :ok = :counters.add(starts, 1, 1)
          Process.sleep(60_000)
          {:ok, :v}
        end

        :ok = RehydratingCache.register_function(fun, key, 60, 30)
      end)

      # Each task starts once on registration and then blocks (stuck).
      assert eventually(fn -> :counters.get(starts, 1) == 6 end)

      # Advance past a full second so the 0ms runtime timeout marks them stuck,
      # then drive one tick. Without cap gating on the restart path all six would
      # be killed and respawned; with it only max_spawns_per_run (3) restart.
      Process.sleep(1_100)
      send(RehydratingCache.name(), :run)
      Process.sleep(300)

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
