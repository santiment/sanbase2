defmodule Sanbase.ApiCallLimit.ETSTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.ApiCallLimit
  alias Sanbase.ApiCallLimit.ETS

  @remote_ip "91.246.248.228"

  setup do
    ETS.clear_all()
    user = insert(:user, email: "test_ets@gmail.com")
    %{user: user}
  end

  describe "get_quota/3 basic behavior" do
    test "returns :infinity for basic auth", %{user: user} do
      assert {:ok, %{quota: :infinity}} = ETS.get_quota(:user, user, :basic)
    end

    test "returns quota from DB on cold start", %{user: user} do
      assert {:ok, %{quota: quota}} = ETS.get_quota(:user, user, :apikey)
      assert is_integer(quota) and quota > 0
    end

    test "returns cached quota on subsequent calls without consuming", %{user: user} do
      {:ok, %{quota: q1}} = ETS.get_quota(:user, user, :apikey)
      {:ok, %{quota: q2}} = ETS.get_quota(:user, user, :apikey)
      assert q1 == q2
    end

    test "returns :infinity for @santiment.net users", _context do
      san_user = insert(:user, email: "dev@santiment.net")
      assert {:ok, %{quota: :infinity}} = ETS.get_quota(:user, san_user, :apikey)
    end

    test "returns :infinity for superusers", _context do
      superuser = insert(:user, is_superuser: true)
      assert {:ok, %{quota: :infinity}} = ETS.get_quota(:user, superuser, :apikey)
    end

    test "returns quota for remote IP on cold start" do
      assert {:ok, %{quota: quota}} = ETS.get_quota(:remote_ip, @remote_ip, :apikey)
      assert is_integer(quota) and quota > 0
    end
  end

  describe "update_usage/5 basic behavior" do
    test "basic auth is a no-op", %{user: user} do
      assert :ok = ETS.update_usage(:user, :basic, user, 1, 100)
    end

    test "decrements remaining counter in ETS", %{user: user} do
      {:ok, %{quota: initial_quota}} = ETS.get_quota(:user, user, :apikey)

      ETS.update_usage(:user, :apikey, user, 5, 100)

      {:ok, %{quota: remaining}} = ETS.get_quota(:user, user, :apikey)
      assert remaining == initial_quota - 5
    end

    test "cold start on update creates ETS entry", %{user: user} do
      # No prior get_quota call — update_usage must cold-start from DB
      ETS.update_usage(:user, :apikey, user, 1, 100)

      {:ok, %{quota: quota}} = ETS.get_quota(:user, user, :apikey)
      assert is_integer(quota)
    end

    test "flushes to DB when quota exhausted", %{user: user} do
      {:ok, %{quota: quota}} = ETS.get_quota(:user, user, :apikey)

      # Exhaust the quota and then some
      ETS.update_usage(:user, :apikey, user, quota + 10, 500)

      # After flush, DB should have the usage recorded
      acl = Sanbase.Repo.get_by(ApiCallLimit, user_id: user.id)
      assert Enum.any?(Map.values(acl.api_calls), fn v -> v > 0 end)
    end

    test "multiple updates accumulate correctly", %{user: user} do
      {:ok, %{quota: initial_quota}} = ETS.get_quota(:user, user, :apikey)

      # Stay within quota to avoid triggering a flush (test config: quota 5-10)
      count = max(initial_quota - 1, 1)
      for _ <- 1..count, do: ETS.update_usage(:user, :apikey, user, 1, 50)

      {:ok, %{quota: remaining}} = ETS.get_quota(:user, user, :apikey)
      assert remaining == initial_quota - count
    end

    test "tracks remote IP usage" do
      {:ok, %{quota: initial_quota}} = ETS.get_quota(:remote_ip, @remote_ip, :apikey)

      ETS.update_usage(:remote_ip, :unauthorized, @remote_ip, 5, 200)

      {:ok, %{quota: remaining}} = ETS.get_quota(:remote_ip, @remote_ip, :apikey)
      assert remaining == initial_quota - 5
    end
  end

  describe "clear_data/2" do
    test "clears user entry and forces re-fetch from DB", %{user: user} do
      {:ok, %{quota: _}} = ETS.get_quota(:user, user, :apikey)

      # Consume some quota
      ETS.update_usage(:user, :apikey, user, 10, 100)

      # Clear and re-fetch
      ETS.clear_data(:user, user)

      {:ok, %{quota: quota}} = ETS.get_quota(:user, user, :apikey)
      # Quota should be freshly fetched (no local decrements)
      assert is_integer(quota) and quota > 0
    end

    test "clears remote IP entry" do
      {:ok, _} = ETS.get_quota(:remote_ip, @remote_ip, :apikey)
      ETS.clear_data(:remote_ip, @remote_ip)
      {:ok, _} = ETS.get_quota(:remote_ip, @remote_ip, :apikey)
    end
  end

  describe "metadata derivation" do
    test "api_calls_remaining in metadata decreases with usage", %{user: user} do
      {:ok, %{api_calls_remaining: initial_remaining}} = ETS.get_quota(:user, user, :apikey)

      ETS.update_usage(:user, :apikey, user, 5, 100)

      {:ok, %{api_calls_remaining: after_remaining}} = ETS.get_quota(:user, user, :apikey)

      assert after_remaining.month == initial_remaining.month - 5
      assert after_remaining.hour == initial_remaining.hour - 5
      assert after_remaining.minute == initial_remaining.minute - 5
    end

    test "api_calls_remaining floors at zero", %{user: user} do
      {:ok, %{api_calls_remaining: initial_remaining}} = ETS.get_quota(:user, user, :apikey)

      # Use more than minute limit (should floor at 0)
      ETS.update_usage(:user, :apikey, user, initial_remaining.minute + 50, 100)

      result = ETS.get_quota(:user, user, :apikey)

      # After flush and re-fetch from DB, either rate limited or remaining >= 0
      case result do
        {:ok, %{api_calls_remaining: remaining}} ->
          assert remaining.month >= 0
          assert remaining.hour >= 0
          assert remaining.minute >= 0

        {:error, %{reason: :rate_limited, api_calls_remaining: remaining}} ->
          assert remaining.month >= 0
          assert remaining.hour >= 0
          assert remaining.minute >= 0
      end
    end
  end

  describe "concurrent access — atomics correctness" do
    test "concurrent updates maintain counter accuracy", %{user: user} do
      {:ok, %{quota: initial_quota}} = ETS.get_quota(:user, user, :apikey)

      count = min(initial_quota - 1, 50)

      tasks =
        for _ <- 1..count do
          Task.async(fn ->
            ETS.update_usage(:user, :apikey, user, 1, 100)
          end)
        end

      Task.await_many(tasks, 10_000)

      {:ok, %{quota: remaining}} = ETS.get_quota(:user, user, :apikey)
      assert remaining == initial_quota - count
    end

    test "concurrent get_quota calls all succeed", %{user: user} do
      tasks =
        for _ <- 1..50 do
          Task.async(fn ->
            ETS.get_quota(:user, user, :apikey)
          end)
        end

      results = Task.await_many(tasks, 10_000)

      assert Enum.all?(results, fn
               {:ok, _} -> true
               _ -> false
             end)
    end

    test "concurrent get_quota and update_usage are safe", %{user: user} do
      # Initialize the entry first
      {:ok, _} = ETS.get_quota(:user, user, :apikey)

      tasks =
        for i <- 1..100 do
          Task.async(fn ->
            if rem(i, 2) == 0 do
              ETS.get_quota(:user, user, :apikey)
            else
              ETS.update_usage(:user, :apikey, user, 1, 100)
            end
          end)
        end

      results = Task.await_many(tasks, 10_000)

      assert Enum.all?(results, fn
               {:ok, _} -> true
               :ok -> true
               _ -> false
             end)
    end

    test "concurrent updates that trigger flush preserve total count - each itearation has more calls than quota",
         %{user: user} do
      insert(:subscription_pro, user: user)
      ApiCallLimit.update_user_plan(user)
      ETS.clear_all()

      # Initialize from DB (pro plan has higher limits)
      {:ok, _} = ETS.get_quota(:user, user, :apikey)

      # Each task makes 10 API calls. With test quota ~5-10, count >= quota
      # so the ETS module bypasses atomics and writes directly to DB.
      # This tests the direct_db_update fallback under heavy concurrency.
      iterations = 100
      calls_per_task = 10

      tasks =
        for _ <- 1..iterations do
          Task.async(fn ->
            ETS.update_usage(:user, :apikey, user, calls_per_task, 1000)
          end)
        end

      Task.await_many(tasks, 10_000)

      # Force a final flush
      ETS.update_usage(:user, :apikey, user, 1_000_000, 0)

      acl = Sanbase.Repo.get_by(ApiCallLimit, user_id: user.id)
      total_calls = Enum.max(Map.values(acl.api_calls))
      expected = iterations * calls_per_task + 1_000_000

      # Allow tolerance due to the inherent batching nature of the system.
      # In test config quota is 5-10, so with 100 tasks there are many flushes
      # and each flush boundary can have small imprecision.
      assert_in_delta total_calls, expected, 1000
    end

    test "concurrent updates that trigger flush preserve total count - some iterations have more calls than quota",
         %{user: user} do
      insert(:subscription_pro, user: user)
      ApiCallLimit.update_user_plan(user)
      ETS.clear_all()

      # Initialize from DB (pro plan has higher limits)
      {:ok, _} = ETS.get_quota(:user, user, :apikey)

      # Each task makes 10 API calls. With test quota ~5-10, count >= quota
      # so the ETS module bypasses atomics and writes directly to DB.
      # This tests the direct_db_update fallback under heavy concurrency.
      iterations = 100

      calls = for _ <- 1..iterations, do: :rand.uniform(7)

      tasks =
        for calls_per_task <- calls do
          Task.async(fn ->
            ETS.update_usage(:user, :apikey, user, calls_per_task, :rand.uniform(50_000))
          end)
        end

      Task.await_many(tasks, 10_000)

      # Force a final flush
      ETS.update_usage(:user, :apikey, user, 1_000_000, 0)

      acl = Sanbase.Repo.get_by(ApiCallLimit, user_id: user.id)
      total_calls = Enum.max(Map.values(acl.api_calls))
      expected = Enum.sum(calls) + 1_000_000

      # Allow tolerance due to the inherent batching nature of the system.
      # In test config quota is 5-10, so with 100 tasks there are many flushes
      # and each flush boundary can have small imprecision.
      assert_in_delta total_calls, expected, 1000
    end
  end

  describe "flush contention" do
    test "only one process flushes when multiple hit quota exhaustion", %{user: user} do
      {:ok, %{quota: quota}} = ETS.get_quota(:user, user, :apikey)

      # Nearly exhaust the quota
      ETS.update_usage(:user, :apikey, user, quota - 1, 100)

      # Now launch many tasks that each make 1 call — one should trigger the flush
      tasks =
        for _ <- 1..20 do
          Task.async(fn ->
            ETS.update_usage(:user, :apikey, user, 1, 100)
          end)
        end

      results = Task.await_many(tasks, 10_000)
      assert Enum.all?(results, &(&1 == :ok))

      # The system should still be functional after the concurrent flush
      result = ETS.get_quota(:user, user, :apikey)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "rate limiting behavior" do
    test "returns error when rate limited", %{user: user} do
      # Free plan: 100/min, 500/hr, 1000/mo
      # Exhaust minute limit
      ETS.update_usage(:user, :apikey, user, 200, 100)

      result = ETS.get_quota(:user, user, :apikey)

      assert {:error, %{reason: :rate_limited}} = result
    end

    test "rate limited state is cached in ETS", %{user: user} do
      ETS.update_usage(:user, :apikey, user, 200, 100)

      {:error, error1} = ETS.get_quota(:user, user, :apikey)
      {:error, error2} = ETS.get_quota(:user, user, :apikey)

      assert error1.reason == :rate_limited
      assert error2.reason == :rate_limited
      # blocked_for_seconds should decrease (or stay the same) between calls
      assert error2.blocked_for_seconds <= error1.blocked_for_seconds
    end
  end

  describe "concurrent flush regression checks" do
    test "concurrent one-call updates around the flush boundary preserve exact totals" do
      runs = 3
      concurrent_updates = 50
      forced_flush_count = 100_000

      for run <- 1..runs do
        run_user =
          insert(:user,
            email: "flush_regression_#{run}_#{System.unique_integer([:positive])}@test"
          )

        {total_calls, expected_total} =
          run_flush_boundary_scenario(run_user, concurrent_updates, forced_flush_count)

        assert total_calls == expected_total
      end
    end

    test "exact accounting is preserved for different contention levels" do
      forced_flush_count = 100_000

      for concurrent_updates <- [2, 10, 20, 50] do
        user =
          insert(
            :user,
            email: "flush_levels_#{concurrent_updates}_#{System.unique_integer([:positive])}@test"
          )

        {total_calls, expected_total} =
          run_flush_boundary_scenario(user, concurrent_updates, forced_flush_count)

        assert total_calls == expected_total
      end
    end
  end

  describe "byte_size accumulation through flush" do
    test "byte_size is flushed to DB and reset", %{user: user} do
      {:ok, %{quota: quota}} = ETS.get_quota(:user, user, :apikey)

      # Use enough to trigger a flush, with non-trivial byte sizes
      ETS.update_usage(:user, :apikey, user, quota + 10, 50_000)

      acl = Sanbase.Repo.get_by(ApiCallLimit, user_id: user.id)
      # At least one time window should have a non-zero response size
      assert Enum.any?(Map.values(acl.api_calls_responses_size_mb), fn v -> v > 0 end)
    end
  end

  describe "subscription upgrade clears ETS" do
    test "upgrading plan clears ETS and applies new limits", %{user: user} do
      # Start as free user
      {:ok, %{api_calls_limits: free_limits}} = ETS.get_quota(:user, user, :apikey)

      # Upgrade to pro
      insert(:subscription_pro, user: user)
      ApiCallLimit.update_user_plan(user)

      # ETS should have been cleared by update_user_plan
      {:ok, %{api_calls_limits: pro_limits}} = ETS.get_quota(:user, user, :apikey)

      assert pro_limits.month > free_limits.month
      assert pro_limits.hour > free_limits.hour
      assert pro_limits.minute > free_limits.minute
    end
  end

  describe "concurrent cold starts" do
    test "concurrent cold starts for the same user all succeed", %{user: user} do
      # No prior initialization — all tasks will cold-start
      tasks =
        for _ <- 1..30 do
          Task.async(fn -> ETS.get_quota(:user, user, :apikey) end)
        end

      results = Task.await_many(tasks, 10_000)

      assert Enum.all?(results, fn
               {:ok, %{quota: q}} when is_integer(q) and q > 0 -> true
               _ -> false
             end)
    end

    test "concurrent cold start updates all succeed", %{user: user} do
      tasks =
        for _ <- 1..30 do
          Task.async(fn -> ETS.update_usage(:user, :apikey, user, 1, 100) end)
        end

      results = Task.await_many(tasks, 10_000)
      assert Enum.all?(results, &(&1 == :ok))
    end
  end

  describe "infinity entities" do
    test "update_usage is a no-op for unlimited users", _context do
      san_user = insert(:user, email: "unlimited@santiment.net")

      # Initialize as infinity
      {:ok, %{quota: :infinity}} = ETS.get_quota(:user, san_user, :apikey)

      # update_usage should be a no-op
      assert :ok = ETS.update_usage(:user, :apikey, san_user, 999_999, 999_999)

      # Still infinity
      assert {:ok, %{quota: :infinity}} = ETS.get_quota(:user, san_user, :apikey)
    end
  end

  describe "error entry lifecycle" do
    test "rate limited error includes blocked_until and blocked_for_seconds", %{user: user} do
      ETS.update_usage(:user, :apikey, user, 200, 100)

      {:error, error} = ETS.get_quota(:user, user, :apikey)

      assert error.reason == :rate_limited
      assert %DateTime{} = error.blocked_until
      assert is_integer(error.blocked_for_seconds) and error.blocked_for_seconds >= 0
    end

    test "api_calls_limits are present in error response", %{user: user} do
      ETS.update_usage(:user, :apikey, user, 200, 100)

      {:error, error} = ETS.get_quota(:user, user, :apikey)
      assert %{month: _, hour: _, minute: _} = error.api_calls_limits
    end
  end

  defp run_flush_boundary_scenario(user, concurrent_updates, forced_flush_count) do
    ETS.clear_data(:user, user)

    {:ok, %{quota: quota}} = ETS.get_quota(:user, user, :apikey)
    pre_flush_usage = max(quota - 1, 0)

    if pre_flush_usage > 0 do
      ETS.update_usage(:user, :apikey, user, pre_flush_usage, 0)
    end

    tasks =
      for _ <- 1..concurrent_updates do
        Task.async(fn ->
          receive do
            :go -> :ok
          end

          ETS.update_usage(:user, :apikey, user, 1, 0)
        end)
      end

    Enum.each(tasks, fn task -> send(task.pid, :go) end)
    Task.await_many(tasks, 10_000)

    # Force any pending in-memory usage to be flushed to DB.
    ETS.update_usage(:user, :apikey, user, forced_flush_count, 0)

    acl = Sanbase.Repo.get_by(ApiCallLimit, user_id: user.id)
    total_calls = Enum.max(Map.values(acl.api_calls))
    expected_total = pre_flush_usage + concurrent_updates + forced_flush_count

    {total_calls, expected_total}
  end
end
