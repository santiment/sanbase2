defmodule SanbaseWeb.Graphql.CachexBoundEnforcerTest do
  use ExUnit.Case, async: true

  alias SanbaseWeb.Graphql.CachexBoundEnforcer

  setup do
    # Unique cache name per test so entries never leak between async tests.
    # `start_supervised!` shuts the Cachex supervisor down gracefully at the end
    # of the test — brutally killing it makes its courier/eternal children log
    # `(stop) killed` crash reports.
    cache = :"cachex_bound_enforcer_test_#{System.unique_integer([:positive])}"
    start_supervised!(%{id: cache, start: {Cachex, :start_link, [cache, []]}})

    %{cache: cache}
  end

  test "enforce returns :ok for a cache with no registered bound" do
    assert :ok == CachexBoundEnforcer.enforce(:some_unregistered_cache_name)
  end

  test "enforce returns :ok while under the bound", %{cache: cache} do
    CachexBoundEnforcer.register(cache, 100, 0.3)

    for i <- 1..50, do: Cachex.put(cache, "key_#{i}", i)

    assert :ok == CachexBoundEnforcer.enforce(cache)
  end

  test "enforce over the bound prunes asynchronously and reports :over_soft_limit", %{
    cache: cache
  } do
    CachexBoundEnforcer.register(cache, 100, 0.3)

    # Raw Cachex.put bypasses the provider, so nothing prunes while filling
    for i <- 1..105, do: Cachex.put(cache, "key_#{i}", i)

    assert :over_soft_limit == CachexBoundEnforcer.enforce(cache)

    # The single-flight pruner runs in a spawned process
    assert eventually(fn -> Cachex.size!(cache) <= 100 - round(100 * 0.3) end)
  end

  test "enforce past the hard ceiling reports :over_hard_limit", %{cache: cache} do
    CachexBoundEnforcer.register(cache, 100, 0.3)

    # 1.1 × 100 = 110 is the hard ceiling; go beyond it
    for i <- 1..150, do: Cachex.put(cache, "key_#{i}", i)

    assert :over_hard_limit == CachexBoundEnforcer.enforce(cache)
  end

  test "the pruner re-checks the bound after finishing, converging without further writes", %{
    cache: cache
  } do
    CachexBoundEnforcer.register(cache, 100, 0.3)

    for i <- 1..500, do: Cachex.put(cache, "key_#{i}", i)

    CachexBoundEnforcer.enforce(cache)

    # A single enforce call must be enough — the pruner loops until under bound
    assert eventually(fn -> Cachex.size!(cache) <= 100 end)
  end

  defp eventually(condition_fun, attempts \\ 50)

  defp eventually(_condition_fun, 0), do: false

  defp eventually(condition_fun, attempts) do
    if condition_fun.() do
      true
    else
      Process.sleep(50)
      eventually(condition_fun, attempts - 1)
    end
  end
end
