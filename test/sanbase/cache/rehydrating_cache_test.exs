defmodule Sanbase.Cache.RehydratingCacheTest do
  # `Sanbase.Cache.RehydratingCache` registers itself under a fixed name
  # (`:__rehydrating_cache__`), and its store/task supervisor are similarly
  # fixed-named. Two instances cannot coexist, so this file runs serially.
  use ExUnit.Case, async: false

  alias Sanbase.Cache.RehydratingCache

  setup do
    # Fresh supervisor per test. No manual `stop_supervised` needed: ExUnit tracks
    # everything started via `start_supervised!/1` under a test-owned supervisor
    # and shuts them down in reverse start order when the test exits (pass, fail,
    # or crash). That tears down the RC GenServer, its ConCache store, and the
    # Task.Supervisor — so no state (or in-progress task child) survives into the
    # next test.
    start_supervised!(Sanbase.Cache.RehydratingCache.Supervisor)
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

      # First attempt dies — waiting caller times out.
      assert {:error, :timeout} = RehydratingCache.get(key, 300)

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
