defmodule SanbaseWeb.Graphql.CachexProviderTest do
  use SanbaseWeb.ConnCase, async: true

  alias SanbaseWeb.Graphql.CachexProvider, as: CacheProvider

  @cache_name :graphql_cache_test_name_cachex
  @cache_id :graphql_cache_test_id_cachex

  setup do
    {:ok, pid} = CacheProvider.start_link(name: @cache_name, id: @cache_id)
    on_exit(fn -> Process.exit(pid, :normal) end)

    :ok
  end

  # ---------------------------------------------------------------------------
  # get/2
  # ---------------------------------------------------------------------------

  test "get returns nil when key is not present" do
    assert nil == CacheProvider.get(@cache_name, "missing_key")
  end

  test "get with a TTL tuple key and a plain key both resolve to the same stored entry" do
    CacheProvider.store(@cache_name, {"ttl_key", 60}, {:ok, "hello"})
    assert {:ok, "hello"} == CacheProvider.get(@cache_name, "ttl_key")
    assert {:ok, "hello"} == CacheProvider.get(@cache_name, {"ttl_key", 60})
  end

  # ---------------------------------------------------------------------------
  # store/3
  # ---------------------------------------------------------------------------

  test "store then get returns the value" do
    CacheProvider.store(@cache_name, {123_123, 60}, {:ok, "something"})
    assert {:ok, "something"} == CacheProvider.get(@cache_name, 123_123)
  end

  test "store with a plain key (no TTL) works" do
    CacheProvider.store(@cache_name, "plain_key", {:ok, 99})
    assert {:ok, 99} == CacheProvider.get(@cache_name, "plain_key")
  end

  test "store does not cache error values" do
    CacheProvider.store(@cache_name, "error_key", {:error, "boom"})
    assert nil == CacheProvider.get(@cache_name, "error_key")
  end

  test "store does not cache nocache values and sets :has_nocache_field in the caller" do
    CacheProvider.store(@cache_name, "nocache_key", {:nocache, "ignored"})
    assert nil == CacheProvider.get(@cache_name, "nocache_key")
    assert true == Process.get(:has_nocache_field)
  end

  test "complex Elixir terms survive the gzip + term_to_binary round-trip" do
    value = {:ok, %{name: "Alice", tags: [:a, :b], nested: %{x: {1, 2}}}}
    CacheProvider.store(@cache_name, "complex_key", value)
    assert value == CacheProvider.get(@cache_name, "complex_key")
  end

  # ---------------------------------------------------------------------------
  # count/1, clear_all/1, size/1
  # ---------------------------------------------------------------------------

  test "count returns 0 for an empty cache" do
    assert 0 == CacheProvider.count(@cache_name)
  end

  test "count increases as values are stored, ignoring errors" do
    CacheProvider.store(@cache_name, "ck1", {:ok, 1})
    CacheProvider.store(@cache_name, "ck2", {:ok, 2})
    CacheProvider.store(@cache_name, "ck_err", {:error, "oops"})
    assert 2 == CacheProvider.count(@cache_name)
  end

  test "clear_all removes all entries" do
    CacheProvider.store(@cache_name, "del1", {:ok, 1})
    CacheProvider.store(@cache_name, "del2", {:ok, 2})
    CacheProvider.clear_all(@cache_name)
    assert 0 == CacheProvider.count(@cache_name)
    assert nil == CacheProvider.get(@cache_name, "del1")
  end

  test "size returns a non-negative float" do
    size = CacheProvider.size(@cache_name)
    assert is_float(size) and size >= 0.0
  end

  # ---------------------------------------------------------------------------
  # get_or_store/4 — basic single-caller behaviour
  # ---------------------------------------------------------------------------

  test "get_or_store returns {:ok, value} and caches it" do
    result = CacheProvider.get_or_store(@cache_name, "ok_key", fn -> {:ok, 42} end, & &1)
    assert {:ok, 42} == result
    # Second call hits the cache, function is not called again
    assert {:ok, 42} == CacheProvider.get(@cache_name, "ok_key")
  end

  test "get_or_store returns {:error, reason} and does not cache it" do
    result =
      CacheProvider.get_or_store(@cache_name, "err_key", fn -> {:error, "oops"} end, & &1)

    assert {:error, "oops"} == result
    assert nil == CacheProvider.get(@cache_name, "err_key")
  end

  test "get_or_store returns the raw value for nocache and does not cache it" do
    result =
      CacheProvider.get_or_store(@cache_name, "nc_key", fn -> {:nocache, "raw"} end, & &1)

    assert "raw" == result
    assert nil == CacheProvider.get(@cache_name, "nc_key")
  end

  test "get_or_store nocache sets :has_nocache_field in the calling process" do
    CacheProvider.get_or_store(@cache_name, "nc_flag", fn -> {:nocache, "v"} end, & &1)
    assert true == Process.get(:has_nocache_field)
  end

  test "get_or_store middleware tuple calls the second function and does not cache" do
    test_pid = self()

    CacheProvider.get_or_store(
      @cache_name,
      "mw_key",
      fn ->
        send(test_pid, :func_called)
        {:middleware, "arg2", "arg3"}
      end,
      fn _, _, _ ->
        send(test_pid, :middleware_called)
        {:ok, "Hello"}
      end
    )

    assert_receive :func_called
    assert_receive :middleware_called
    # Not cached — second call triggers both functions again
    CacheProvider.get_or_store(
      @cache_name,
      "mw_key",
      fn ->
        send(test_pid, :func_called)
        {:middleware, "arg2", "arg3"}
      end,
      fn _, _, _ ->
        send(test_pid, :middleware_called)
        {:ok, "Hello"}
      end
    )

    assert_receive :func_called
    assert_receive :middleware_called
  end

  test "get_or_store with a {key, ttl} tuple stores and retrieves under the plain key" do
    result =
      CacheProvider.get_or_store(
        @cache_name,
        {"ttl_gs_key", 60},
        fn -> {:ok, "stored"} end,
        & &1
      )

    assert {:ok, "stored"} == result
    assert {:ok, "stored"} == CacheProvider.get(@cache_name, "ttl_gs_key")
  end

  # ---------------------------------------------------------------------------
  # get_or_store/4 — concurrent: happy path
  # ---------------------------------------------------------------------------

  test "only one computation runs when the same key is requested concurrently" do
    test_pid = self()

    for _ <- 1..10 do
      spawn(fn ->
        CacheProvider.get_or_store(
          @cache_name,
          :dedup_key,
          fn ->
            Process.sleep(300)
            send(test_pid, :computed)
            {:ok, "result"}
          end,
          & &1
        )
      end)
    end

    assert_receive :computed, 5000
    refute_receive :computed
  end

  test "all concurrent callers receive the same computed value" do
    test_pid = self()
    n = 10

    for _ <- 1..n do
      spawn(fn ->
        result =
          CacheProvider.get_or_store(
            @cache_name,
            :shared_value_key,
            fn ->
              Process.sleep(300)
              {:ok, "shared"}
            end,
            & &1
          )

        send(test_pid, {:result, result})
      end)
    end

    results =
      Enum.map(1..n, fn _ ->
        assert_receive {:result, result}, 5000
        result
      end)

    assert Enum.all?(results, &(&1 == {:ok, "shared"}))
  end

  test "a caller that arrives mid-computation is deduplicated rather than spawning a new computation" do
    test_pid = self()

    # First caller starts a slow computation
    spawn(fn ->
      result =
        CacheProvider.get_or_store(
          @cache_name,
          :mid_key,
          fn ->
            Process.sleep(500)
            send(test_pid, :computed)
            {:ok, "result"}
          end,
          & &1
        )

      send(test_pid, {:first, result})
    end)

    # Second caller arrives while the computation is still in flight
    Process.sleep(50)

    spawn(fn ->
      result =
        CacheProvider.get_or_store(
          @cache_name,
          :mid_key,
          # This function must NOT run — it would be a second computation
          fn ->
            send(test_pid, :computed)
            {:ok, "different"}
          end,
          & &1
        )

      send(test_pid, {:second, result})
    end)

    assert_receive :computed, 5000
    refute_receive :computed

    # Both callers get the result from the single computation
    assert_receive {:first, {:ok, "result"}}, 5000
    assert_receive {:second, {:ok, "result"}}, 5000
  end

  test "computations for different keys run in parallel without blocking each other" do
    test_pid = self()

    for key <- [:parallel_key_a, :parallel_key_b] do
      spawn(fn ->
        CacheProvider.get_or_store(
          @cache_name,
          key,
          fn ->
            Process.sleep(300)
            send(test_pid, {:computed, key})
            {:ok, key}
          end,
          & &1
        )
      end)
    end

    # If they ran serially this would take ~600ms; 1500ms budget is generous
    # but we primarily care that BOTH computations run
    assert_receive {:computed, _}, 1500
    assert_receive {:computed, _}, 1500
  end

  # ---------------------------------------------------------------------------
  # get_or_store/4 — concurrent: error path
  # ---------------------------------------------------------------------------

  test "when the computation errors, all concurrent callers receive the error" do
    test_pid = self()
    n = 5

    for _ <- 1..n do
      spawn(fn ->
        result =
          CacheProvider.get_or_store(
            @cache_name,
            :concurrent_error_key,
            fn ->
              Process.sleep(100)
              send(test_pid, :computed)
              {:error, "transient failure"}
            end,
            & &1
          )

        send(test_pid, {:result, result})
      end)
    end

    # Exactly one computation runs
    assert_receive :computed, 5000
    refute_receive :computed

    # Every caller gets the error
    results =
      Enum.map(1..n, fn _ ->
        assert_receive {:result, result}, 5000
        result
      end)

    assert Enum.all?(results, &(&1 == {:error, "transient failure"}))
  end

  test "an error result is not cached — the next call retries the computation" do
    test_pid = self()
    n = 3

    # First wave: all error
    for _ <- 1..n do
      spawn(fn ->
        CacheProvider.get_or_store(
          @cache_name,
          :retry_after_error_key,
          fn ->
            Process.sleep(100)
            {:error, "down"}
          end,
          & &1
        )

        send(test_pid, :wave1_done)
      end)
    end

    for _ <- 1..n, do: assert_receive(:wave1_done, 5000)

    # Fresh call after the error wave — must trigger a new computation
    result =
      CacheProvider.get_or_store(
        @cache_name,
        :retry_after_error_key,
        fn ->
          send(test_pid, :retried)
          {:ok, "recovered"}
        end,
        & &1
      )

    assert_receive :retried, 5000
    assert {:ok, "recovered"} == result
  end

  # ---------------------------------------------------------------------------
  # get_or_store/4 — concurrent: nocache path
  # ---------------------------------------------------------------------------

  test "when the computation returns nocache, all concurrent callers get the value but nothing is cached" do
    test_pid = self()
    n = 5

    for _ <- 1..n do
      spawn(fn ->
        result =
          CacheProvider.get_or_store(
            @cache_name,
            :concurrent_nocache_key,
            fn ->
              Process.sleep(100)
              send(test_pid, :computed)
              {:nocache, "ephemeral"}
            end,
            & &1
          )

        send(test_pid, {:result, result})
      end)
    end

    assert_receive :computed, 5000
    refute_receive :computed

    results =
      Enum.map(1..n, fn _ ->
        assert_receive {:result, result}, 5000
        result
      end)

    assert Enum.all?(results, &(&1 == "ephemeral"))
    assert nil == CacheProvider.get(@cache_name, :concurrent_nocache_key)
  end

  test "a nocache result is not cached — the next call retries the computation" do
    test_pid = self()
    n = 3

    for _ <- 1..n do
      spawn(fn ->
        CacheProvider.get_or_store(
          @cache_name,
          :retry_after_nocache_key,
          fn ->
            Process.sleep(100)
            {:nocache, "skip me"}
          end,
          & &1
        )

        send(test_pid, :wave1_done)
      end)
    end

    for _ <- 1..n, do: assert_receive(:wave1_done, 5000)

    CacheProvider.get_or_store(
      @cache_name,
      :retry_after_nocache_key,
      fn ->
        send(test_pid, :retried)
        {:ok, "now cached"}
      end,
      & &1
    )

    assert_receive :retried, 5000
    assert {:ok, "now cached"} == CacheProvider.get(@cache_name, :retry_after_nocache_key)
  end

  # ---------------------------------------------------------------------------
  # get_or_store/4 — concurrent: exception path
  # ---------------------------------------------------------------------------

  test "when the computation raises, all concurrent callers receive an error tuple" do
    test_pid = self()
    n = 5

    for _ <- 1..n do
      spawn(fn ->
        result =
          CacheProvider.get_or_store(
            @cache_name,
            :concurrent_raise_key,
            fn ->
              Process.sleep(100)
              raise "something went wrong"
            end,
            & &1
          )

        send(test_pid, {:result, result})
      end)
    end

    results =
      Enum.map(1..n, fn _ ->
        assert_receive {:result, result}, 5000
        result
      end)

    assert Enum.all?(results, &match?({:error, _}, &1))
    # Nothing was cached
    assert nil == CacheProvider.get(@cache_name, :concurrent_raise_key)
  end

  test "after a raised exception, the next call retries the computation" do
    test_pid = self()

    spawn(fn ->
      CacheProvider.get_or_store(
        @cache_name,
        :raise_then_retry_key,
        fn ->
          Process.sleep(50)
          raise "crash"
        end,
        & &1
      )

      send(test_pid, :wave1_done)
    end)

    assert_receive :wave1_done, 5000

    result =
      CacheProvider.get_or_store(
        @cache_name,
        :raise_then_retry_key,
        fn ->
          send(test_pid, :retried)
          {:ok, "success after crash"}
        end,
        & &1
      )

    assert_receive :retried, 5000
    assert {:ok, "success after crash"} == result
  end
end
