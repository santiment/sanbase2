defmodule SanbaseWeb.Graphql.CachexProviderTest do
  use SanbaseWeb.ConnCase, async: false

  alias SanbaseWeb.Graphql.CachexProvider, as: CacheProvider

  @cache_name :graphql_cache_test

  setup do
    {:ok, pid} =
      Supervisor.start_link(
        [Supervisor.Spec.worker(Cachex, [:graphql_cache_test, []])],
        strategy: :one_for_one,
        name: Sanbase.TestCachexSupervisor,
        max_restarts: 5,
        max_seconds: 1
      )

    [supervisor_pid: pid]
  end

  test "return plain nil when no value stored" do
    assert nil == CacheProvider.get(@cache_name, "somekeyj")
  end

  test "return {:ok, value} when {:ok, value} is explicitly stored" do
    key = "somekey"
    value = "something"
    CacheProvider.store(@cache_name, key, {:ok, value})
    assert {:ok, value} == CacheProvider.get(@cache_name, key)
  end

  test "value is actually cached and not precalculated" do
    key = "somekey"
    test_pid = self()

    CacheProvider.get_or_store(
      @cache_name,
      key,
      fn ->
        send(test_pid, "message from precalculation")
        {:ok, "Hello"}
      end,
      & &1
    )

    assert_receive("message from precalculation", 500)

    CacheProvider.get_or_store(
      @cache_name,
      key,
      fn ->
        send(test_pid, "message from precalculation")
        {:ok, "Hello"}
      end,
      & &1
    )

    refute_receive("message from precalculation", 500)
  end

  test "error value is not stored" do
    key = "somekey"
    test_pid = self()

    CacheProvider.get_or_store(
      @cache_name,
      key,
      fn ->
        send(test_pid, "message from precalculation")
        {:error, "Goodbye"}
      end,
      & &1
    )

    assert_receive("message from precalculation", 500)

    CacheProvider.get_or_store(
      @cache_name,
      key,
      fn ->
        send(test_pid, "message from precalculation")
        {:error, "Goodbye"}
      end,
      & &1
    )

    assert_receive("message from precalculation", 500)
  end

  test "the second function is called in case of :middleware tuple" do
    key = "somekey"
    test_pid = self()

    CacheProvider.get_or_store(
      @cache_name,
      key,
      fn ->
        send(test_pid, "message from precalculation")
        {:middleware, "fake second arg", "fake third arg"}
      end,
      fn _, _, _ ->
        send(test_pid, "message from the other function")
        {:ok, "Hello"}
      end
    )

    assert_receive("message from precalculation", 500)
    assert_receive("message from the other function", 500)
  end
end
