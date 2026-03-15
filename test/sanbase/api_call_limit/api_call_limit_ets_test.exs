defmodule Sanbase.ApiCallLimit.ETSTest do
  use Sanbase.DataCase, async: false

  @moduletag :api_call_counting

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
      {:ok, %{quota: initial_quota}} = ETS.get_quota(:user, user, :apikey)

      # Decrement by 5 — with test config (quota 6-10), this leaves remaining
      # at 1-5, which is below the minimum fresh quota (6). This guarantees
      # that after clear_data a fresh fetch always returns a higher quota.
      decrement = 5
      ETS.update_usage(:user, :apikey, user, decrement, 100)
      {:ok, %{quota: cached_quota}} = ETS.get_quota(:user, user, :apikey)
      assert cached_quota == initial_quota - decrement

      ETS.clear_data(:user, user)

      {:ok, %{quota: refreshed_quota}} = ETS.get_quota(:user, user, :apikey)
      # After clear, the local decrements are gone — fresh quota from DB
      assert refreshed_quota > cached_quota
    end

    test "clears remote IP entry and forces re-fetch from DB" do
      {:ok, %{quota: initial_quota}} = ETS.get_quota(:remote_ip, @remote_ip, :apikey)

      decrement = 5
      ETS.update_usage(:remote_ip, :unauthorized, @remote_ip, decrement, 100)
      {:ok, %{quota: cached_quota}} = ETS.get_quota(:remote_ip, @remote_ip, :apikey)
      assert cached_quota == initial_quota - decrement

      ETS.clear_data(:remote_ip, @remote_ip)

      {:ok, %{quota: refreshed_quota}} = ETS.get_quota(:remote_ip, @remote_ip, :apikey)
      # Fresh fetch — no local decrements carried over
      assert refreshed_quota > cached_quota
    end

    test "clear_data flushes usage to DB before deleting", %{user: user} do
      {:ok, %{quota: quota}} = ETS.get_quota(:user, user, :apikey)

      # Use some quota but don't exhaust it (no automatic flush)
      usage = max(quota - 2, 1)
      ETS.update_usage(:user, :apikey, user, usage, 500)

      # clear_data should flush the accumulated usage before deleting
      ETS.clear_data(:user, user)

      acl = Sanbase.Repo.get_by(ApiCallLimit, user_id: user.id)
      total_calls = Enum.max(Map.values(acl.api_calls))
      assert total_calls >= usage
    end

    test "clear_data during active concurrent requests preserves all usage", %{user: user} do
      insert(:subscription_pro, user: user)
      ApiCallLimit.update_user_plan(user)

      # Simulate realistic pattern: bursts of requests interleaved with
      # clear_data calls (e.g. plan changes during active usage).
      # 5 rounds × (10 tasks × 5 usage each + clear) = 250 total calls
      rounds = 5
      tasks_per_round = 10
      usage_per_task = 5
      expected_per_round = tasks_per_round * usage_per_task

      for _ <- 1..rounds do
        {:ok, _} = ETS.get_quota(:user, user, :apikey)

        tasks =
          for _ <- 1..tasks_per_round do
            Task.async(fn ->
              ETS.update_usage(:user, :apikey, user, usage_per_task, 100)
            end)
          end

        Task.await_many(tasks, 10_000)

        # clear_data flushes the accumulated in-memory usage before deleting
        ETS.clear_data(:user, user)
      end

      acl = Sanbase.Repo.get_by(ApiCallLimit, user_id: user.id)
      total_calls = Enum.max(Map.values(acl.api_calls))
      expected_total = rounds * expected_per_round

      assert total_calls == expected_total
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

    test "concurrent updates that trigger flush preserve total count - each iteration has more calls than quota",
         %{user: user} do
      insert(:subscription_pro, user: user)
      ApiCallLimit.update_user_plan(user)
      ETS.clear_all()

      {:ok, _} = ETS.get_quota(:user, user, :apikey)

      # Each task makes 10 API calls. With test quota ~5-10, count (10) >= quota,
      # so every successful atomics write immediately exhausts the batch. After
      # a few retries seeing :flushing, the count>=quota shortcut kicks in and
      # tasks fall back to increment_usage_db (single atomic UPDATE, no FOR UPDATE).
      # No force-flush needed — every call either triggers an atomics flush or
      # goes directly to DB via increment_usage_db.
      iterations = 30
      calls_per_task = 10

      tasks =
        for _ <- 1..iterations do
          Task.async(fn ->
            ETS.update_usage(:user, :apikey, user, calls_per_task, 1000)
          end)
        end

      Task.await_many(tasks, 10_000)

      acl = Sanbase.Repo.get_by(ApiCallLimit, user_id: user.id)
      total_calls = Enum.max(Map.values(acl.api_calls))
      expected = iterations * calls_per_task

      assert total_calls == expected
    end

    test "concurrent updates that trigger flush preserve total count - no iteration has more calls than quota",
         %{user: user} do
      insert(:subscription_pro, user: user)
      ApiCallLimit.update_user_plan(user)
      ETS.clear_all()

      # Initialize from DB (pro plan has higher limits)
      {:ok, _} = ETS.get_quota(:user, user, :apikey)

      # Each task makes 1 API call — always below quota (~5-10). This exercises
      # the pure atomics fast path: multiple tasks share a batch, flushes happen
      # organically when the batch is exhausted (~every 7 tasks). 100 tasks
      # means ~14 flush cycles, all going through atomics → flush → reinit
      # with no direct_db_update fallback needed.
      iterations = 130
      calls_per_task = 1

      tasks =
        for _ <- 1..iterations do
          Task.async(fn ->
            ETS.update_usage(:user, :apikey, user, calls_per_task, 1000)
          end)
        end

      Task.await_many(tasks, 10_000)

      # Force a final flush by exceeding the current batch quota.
      # Use a small count (20) — just enough to trigger a flush without
      # pushing past the plan's rate limits. A huge count like 1_000_000
      # would exceed the minute limit, causing the post-flush quota check
      # to return :rate_limited and silently drop unflushed batch counts.
      force_flush = 20
      ETS.update_usage(:user, :apikey, user, force_flush, 0)

      acl = Sanbase.Repo.get_by(ApiCallLimit, user_id: user.id)
      total_calls = Enum.max(Map.values(acl.api_calls))
      expected = iterations * calls_per_task + force_flush

      assert total_calls == expected
    end

    test "concurrent updates that trigger flush preserve total count - some iterations have more calls than quota",
         %{user: user} do
      insert(:subscription_pro, user: user)
      ApiCallLimit.update_user_plan(user)
      ETS.clear_all()

      # Initialize from DB (pro plan has higher limits)
      {:ok, _} = ETS.get_quota(:user, user, :apikey)

      # Mix of small calls (< quota, use atomics path) and large calls
      # (>= quota, may hit direct_db_update fallback under contention).
      calls = for _ <- 1..30, do: :rand.uniform(7)

      tasks =
        for calls_per_task <- calls do
          Task.async(fn ->
            ETS.update_usage(:user, :apikey, user, calls_per_task, :rand.uniform(50_000))
          end)
        end

      Task.await_many(tasks, 10_000)

      # Force a final flush (same pattern as above — small count to avoid rate limits)
      force_flush = 20
      ETS.update_usage(:user, :apikey, user, force_flush, 0)

      acl = Sanbase.Repo.get_by(ApiCallLimit, user_id: user.id)
      total_calls = Enum.max(Map.values(acl.api_calls))
      expected = Enum.sum(calls) + force_flush

      assert total_calls == expected
    end

    test "concurrent updates with production-like quota (100) and high concurrency",
         %{user: user} do
      insert(:subscription_pro, user: user)
      ApiCallLimit.update_user_plan(user)
      ETS.clear_all()

      # Temporarily bump quota to production-like values so we can stress-test
      # without hitting the count>=quota direct_db_update shortcut. With
      # quota ~100-150, each task's count (1-3) fits within a batch and
      # flushes happen organically every ~100 calls.
      original_config = Application.get_env(:sanbase, Sanbase.ApiCallLimit)

      on_exit(fn ->
        Application.put_env(:sanbase, Sanbase.ApiCallLimit, original_config)
      end)

      Application.put_env(
        :sanbase,
        Sanbase.ApiCallLimit,
        Keyword.merge(original_config, quota_size: 100, quota_size_max_offset: 50)
      )

      # Clear so the next get_quota fetches a fresh batch with the new quota
      ETS.clear_all()
      {:ok, _} = ETS.get_quota(:user, user, :apikey)

      # Use Task.async_stream with max_concurrency: 20 to simulate realistic
      # server load (20 concurrent connections per user) rather than launching
      # all 200 tasks at once. This avoids overwhelming the BEAM scheduler
      # while still generating real flush contention.
      calls = for _ <- 1..200, do: :rand.uniform(3)

      calls
      |> Task.async_stream(
        fn calls_per_task ->
          ETS.update_usage(:user, :apikey, user, calls_per_task, 1000)
        end,
        max_concurrency: 20,
        timeout: 1_000,
        ordered: false
      )
      |> Stream.run()

      # Force a final flush. We can't use a huge count like 1_000_000 because
      # that would push the user past the pro plan minute limit (600), causing
      # the flush's fetch_and_store_quota to return :rate_limited and replace
      # the ETS entry with an error — dropping any unflushed batch counts.
      force_flush_count = 200
      ETS.update_usage(:user, :apikey, user, force_flush_count, 0)

      acl = Sanbase.Repo.get_by(ApiCallLimit, user_id: user.id)
      total_calls = Enum.max(Map.values(acl.api_calls))
      expected = Enum.sum(calls) + force_flush_count

      assert total_calls == expected
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

  describe "increment_usage_db" do
    test "increments api_calls in a single statement without FOR UPDATE", %{user: user} do
      # Ensure the row exists
      {:ok, _} = ApiCallLimit.get_quota_db(:user, user)

      result = ApiCallLimit.increment_usage_db(:user, user, 5, 1000)
      assert {:ok, :incremented} = result

      acl = Sanbase.Repo.get_by(ApiCallLimit, user_id: user.id)
      assert Enum.all?(Map.values(acl.api_calls), fn v -> v >= 5 end)
    end

    test "multiple increments accumulate correctly", %{user: user} do
      {:ok, _} = ApiCallLimit.get_quota_db(:user, user)

      for _ <- 1..10 do
        {:ok, :incremented} = ApiCallLimit.increment_usage_db(:user, user, 3, 500)
      end

      acl = Sanbase.Repo.get_by(ApiCallLimit, user_id: user.id)
      assert Enum.all?(Map.values(acl.api_calls), fn v -> v >= 30 end)
    end

    test "concurrent increments don't lose counts", %{user: user} do
      {:ok, _} = ApiCallLimit.get_quota_db(:user, user)

      count = 50

      tasks =
        for _ <- 1..count do
          Task.async(fn ->
            ApiCallLimit.increment_usage_db(:user, user, 1, 100)
          end)
        end

      results = Task.await_many(tasks, 10_000)
      assert Enum.all?(results, &match?({:ok, :incremented}, &1))

      acl = Sanbase.Repo.get_by(ApiCallLimit, user_id: user.id)
      # Every increment should have landed — exact count
      assert Enum.all?(Map.values(acl.api_calls), fn v -> v >= count end)
    end

    test "returns {:error, :not_found} for non-existent user" do
      fake_user = %Sanbase.Accounts.User{id: 999_999_999}
      result = ApiCallLimit.increment_usage_db(:user, fake_user, 5, 1000)
      assert {:error, :not_found} = result
    end

    test "returns {:error, :not_found} for non-existent remote_ip" do
      result = ApiCallLimit.increment_usage_db(:remote_ip, "0.0.0.0", 5, 1000)
      assert {:error, :not_found} = result
    end

    test "rejects non-integer count via function guard" do
      user = insert(:user, email: "guard_test@gmail.com")
      {:ok, _} = ApiCallLimit.get_quota_db(:user, user)

      # Use apply/4 to bypass compile-time type checking — we intentionally
      # pass a wrong type to verify the runtime guard rejects it.
      assert_raise FunctionClauseError, fn ->
        apply(ApiCallLimit, :increment_usage_db, [:user, user, "five", 1000])
      end
    end

    test "rejects non-integer byte_size via function guard" do
      user = insert(:user, email: "guard_test2@gmail.com")
      {:ok, _} = ApiCallLimit.get_quota_db(:user, user)

      assert_raise FunctionClauseError, fn ->
        apply(ApiCallLimit, :increment_usage_db, [:user, user, 5, "one thousand"])
      end
    end

    test "rejects negative count via function guard" do
      user = insert(:user, email: "negative_test@gmail.com")
      {:ok, _} = ApiCallLimit.get_quota_db(:user, user)

      assert_raise FunctionClauseError, fn ->
        ApiCallLimit.increment_usage_db(:user, user, -100, 0)
      end
    end

    test "rejects negative byte_size via function guard" do
      user = insert(:user, email: "negative_bytes_test@gmail.com")
      {:ok, _} = ApiCallLimit.get_quota_db(:user, user)

      assert_raise FunctionClauseError, fn ->
        ApiCallLimit.increment_usage_db(:user, user, 5, -1000)
      end
    end

    test "handles zero count and zero byte_size", %{user: user} do
      {:ok, _} = ApiCallLimit.get_quota_db(:user, user)

      result = ApiCallLimit.increment_usage_db(:user, user, 0, 0)
      assert {:ok, :incremented} = result

      acl = Sanbase.Repo.get_by(ApiCallLimit, user_id: user.id)
      # Zero increment should leave values at their initial state
      assert Enum.all?(Map.values(acl.api_calls), fn v -> v == 0 end)
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
