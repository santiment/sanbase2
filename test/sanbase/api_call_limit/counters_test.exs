defmodule Sanbase.ApiCallLimit.CountersTest do
  use ExUnit.Case, async: true

  @moduletag :api_call_counting

  alias Sanbase.ApiCallLimit.Counters

  describe "new/1" do
    test "creates bucket with given quota" do
      ref = Counters.new(100)
      assert Counters.remaining(ref) == 100
    end

    test "snapshot shows zero usage on fresh bucket" do
      ref = Counters.new(50)
      assert %{api_calls_made: 0, acc_byte_size: 0} = Counters.snapshot(ref, 50)
    end
  end

  describe "update_usage/3" do
    test "decrements remaining and adds byte_size" do
      ref = Counters.new(100)
      assert {:updated, 95} = Counters.update_usage(ref, 5, 200)
      assert Counters.remaining(ref) == 95
      assert %{api_calls_made: 5, acc_byte_size: 200} = Counters.snapshot(ref, 100)
    end

    test "remaining can go negative" do
      ref = Counters.new(3)
      assert {:updated, -2} = Counters.update_usage(ref, 5, 100)
      assert Counters.remaining(ref) == -2
    end

    test "multiple apply_usage calls accumulate" do
      ref = Counters.new(100)
      {:updated, 90} = Counters.update_usage(ref, 10, 100)
      {:updated, 80} = Counters.update_usage(ref, 10, 200)
      {:updated, 70} = Counters.update_usage(ref, 10, 300)

      assert %{api_calls_made: 30, acc_byte_size: 600} = Counters.snapshot(ref, 100)
    end

    test "returns :flushing when flush_lock is held" do
      ref = Counters.new(100)
      :acquired = Counters.acquire_flush_lock(ref)

      assert :flushing = Counters.update_usage(ref, 1, 100)
      # Remaining should not have changed
      assert Counters.remaining(ref) == 100
    end

    test "works again after flush_lock is released" do
      ref = Counters.new(100)
      :acquired = Counters.acquire_flush_lock(ref)
      assert :flushing = Counters.update_usage(ref, 1, 100)

      Counters.release_flush_lock(ref)
      assert {:updated, 99} = Counters.update_usage(ref, 1, 100)
    end
  end

  describe "acquire_flush_lock/1" do
    test "first caller acquires, second is contended" do
      ref = Counters.new(100)
      assert :acquired = Counters.acquire_flush_lock(ref)
      assert :contended = Counters.acquire_flush_lock(ref)
    end

    test "can re-acquire after release" do
      ref = Counters.new(100)
      :acquired = Counters.acquire_flush_lock(ref)
      Counters.release_flush_lock(ref)
      assert :acquired = Counters.acquire_flush_lock(ref)
    end
  end

  describe "wait_for_writers/2" do
    test "returns :drained immediately when no writers" do
      ref = Counters.new(100)
      assert :drained = Counters.wait_for_writers(ref)
    end

    test "waits for in-flight writer to complete" do
      ref = Counters.new(100)

      # Simulate an in-flight writer by directly incrementing the writers slot
      :atomics.add(ref, 4, 1)

      waiter = Task.async(fn -> Counters.wait_for_writers(ref) end)

      # Give the waiter time to start spinning
      Process.sleep(10)

      # "Complete" the writer
      :atomics.sub(ref, 4, 1)

      assert :drained = Task.await(waiter, 5_000)
    end

    test "returns :timeout when writers never drain" do
      ref = Counters.new(100)
      :atomics.add(ref, 4, 1)

      assert :timeout = Counters.wait_for_writers(ref, max_retries: 3, sleep_ms: 1)
    end
  end

  describe "snapshot/2" do
    test "returns correct counts after usage" do
      ref = Counters.new(100)
      Counters.update_usage(ref, 30, 5000)
      Counters.update_usage(ref, 20, 3000)

      assert %{api_calls_made: 50, acc_byte_size: 8000} = Counters.snapshot(ref, 100)
    end

    test "api_calls_made floors at zero even if remaining > quota" do
      # This shouldn't happen in practice but test the guard
      ref = Counters.new(100)
      # remaining is already 100, quota is 50 → would give negative calls_made
      assert %{api_calls_made: 0} = Counters.snapshot(ref, 50)
    end
  end

  describe "concurrent update_usage" do
    test "parallel writers maintain exact count" do
      ref = Counters.new(10_000)
      count = 200

      tasks =
        for _ <- 1..count do
          Task.async(fn -> Counters.update_usage(ref, 1, 50) end)
        end

      results = Task.await_many(tasks, 10_000)

      applied = Enum.count(results, &match?({:updated, _}, &1))
      assert applied == count
      assert Counters.remaining(ref) == 10_000 - count
      assert %{api_calls_made: ^count, acc_byte_size: byte_size} = Counters.snapshot(ref, 10_000)
      assert byte_size == count * 50
    end

    test "writers during flush get :flushing" do
      ref = Counters.new(1000)

      # Some writes succeed before flush
      {:updated, _} = Counters.update_usage(ref, 10, 100)

      # Acquire flush lock
      :acquired = Counters.acquire_flush_lock(ref)

      # Now all writers should see :flushing
      tasks =
        for _ <- 1..20 do
          Task.async(fn -> Counters.update_usage(ref, 1, 10) end)
        end

      results = Task.await_many(tasks, 5_000)
      assert Enum.all?(results, &(&1 == :flushing))

      # Snapshot should only reflect the 10 pre-lock writes
      assert %{api_calls_made: 10, acc_byte_size: 100} = Counters.snapshot(ref, 1000)
    end
  end

  describe "full flusher protocol" do
    test "flusher captures all pre-lock writes in snapshot" do
      ref = Counters.new(100)

      # Writers apply usage
      {:updated, _} = Counters.update_usage(ref, 15, 500)
      {:updated, _} = Counters.update_usage(ref, 25, 800)

      # Flusher acquires lock
      :acquired = Counters.acquire_flush_lock(ref)

      # Writers after lock see :flushing
      assert :flushing = Counters.update_usage(ref, 1, 100)

      # Wait for any in-flight writers (none here, so instant)
      :drained = Counters.wait_for_writers(ref)

      # Snapshot captures exactly the pre-lock writes
      assert %{api_calls_made: 40, acc_byte_size: 1300} = Counters.snapshot(ref, 100)
    end

    test "concurrent writers racing with flush lock are correctly partitioned" do
      ref = Counters.new(10_000)

      # Start many writers that will race with flush lock acquisition
      writer_tasks =
        for _ <- 1..50 do
          Task.async(fn ->
            receive do
              :go -> :ok
            end

            Counters.update_usage(ref, 1, 100)
          end)
        end

      # Acquire the flush lock BEFORE releasing writers — some writers will
      # see the lock and return :flushing, others may slip through before
      # the lock becomes visible to them.
      :acquired = Counters.acquire_flush_lock(ref)

      # Unleash all writers at once
      Enum.each(writer_tasks, fn t -> send(t.pid, :go) end)

      writer_results = Task.await_many(writer_tasks, 10_000)

      applied = Enum.count(writer_results, &match?({:updated, _}, &1))
      flushing = Enum.count(writer_results, &(&1 == :flushing))

      assert applied + flushing == 50
      # With the lock held, all writers should see :flushing
      assert flushing == 50
      assert applied == 0

      # Snapshot should show zero usage since all writers were blocked
      assert %{api_calls_made: 0, acc_byte_size: 0} = Counters.snapshot(ref, 10_000)
    end
  end
end
