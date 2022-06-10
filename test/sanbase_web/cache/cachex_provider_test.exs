defmodule SanbaseWeb.Graphql.CachexProviderTest do
  use SanbaseWeb.ConnCase, async: false

  alias SanbaseWeb.Graphql.CachexProvider, as: CacheProvider

  @cache_name :graphql_cache_test
  @cache_id :graphql_cache_id

  setup do
    {:ok, pid} = CacheProvider.start_link(name: @cache_name, id: @cache_id)
    on_exit(fn -> Process.exit(pid, :normal) end)

    :ok
  end

  test "return plain nil when no value stored" do
    assert nil == CacheProvider.get(@cache_name, "somekeyj")
  end

  test "return {:ok, value} when {:ok, value} is explicitly stored" do
    key = 123_123
    cache_key = {key, 60}
    value = "something"
    CacheProvider.store(@cache_name, cache_key, {:ok, value})
    assert {:ok, value} == CacheProvider.get(@cache_name, key)
  end

  test "value is actually cached and not precalculated" do
    key = {123_123, 60}
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

    assert_receive("message from precalculation")

    CacheProvider.get_or_store(
      @cache_name,
      key,
      fn ->
        send(test_pid, "message from precalculation")
        {:ok, "Hello"}
      end,
      & &1
    )

    refute_receive("message from precalculation")
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

    assert_receive("message from precalculation")

    CacheProvider.get_or_store(
      @cache_name,
      key,
      fn ->
        send(test_pid, "message from precalculation")
        {:error, "Goodbye"}
      end,
      & &1
    )

    assert_receive("message from precalculation")
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

    assert_receive("message from precalculation")
    assert_receive("message from the other function")
  end
end
