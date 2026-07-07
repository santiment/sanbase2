defmodule Sanbase.Metric.AvailableMetricsCircuitBreakerTest do
  # Mocks (meck) patch modules globally, so this file cannot run async. DataCase
  # (not plain ExUnit.Case) because the experimental-metrics filter inside
  # available_metrics_for_selector/2 queries the metric registry in Postgres,
  # and its shared sandbox checkout also covers the parallel Task processes.
  use Sanbase.DataCase, async: false

  alias Sanbase.Metric
  alias Sanbase.Metric.AvailableMetricsCircuitBreaker, as: CircuitBreaker
  alias Sanbase.Metric.Helper

  @moduletag capture_log: true

  @failing_module Sanbase.Twitter.MetricAdapter

  setup do
    # Unique slug per test so the per-module and circuit-breaker cache keys (both
    # keyed by selector) never collide across tests or repeated runs.
    slug = "circuit-breaker-test-#{System.unique_integer([:positive])}"
    {:ok, selector: %{slug: slug}}
  end

  # Thin wrappers over the breaker's API for the failing module under the given
  # selector (access_level "released", no lookback).
  defp breaker_id(selector), do: {@failing_module, selector, "released", nil}
  defp check(selector), do: CircuitBreaker.check(breaker_id(selector))
  defp failure_score(selector), do: CircuitBreaker.failure_score(breaker_id(selector))
  defp last_good(selector), do: CircuitBreaker.last_good(breaker_id(selector))
  defp close(selector), do: CircuitBreaker.close(breaker_id(selector))

  # Mirrors the per-module working-cache key in Sanbase.Metric so a test can
  # force a cache miss and make the fan-out re-probe the module.
  defp module_cache_key(selector) do
    {Sanbase.Metric, :available_metrics_for_selector_in_module, @failing_module, selector,
     "released", nil}
    |> Sanbase.Cache.hash()
  end

  # Mock every metric module: all succeed except @failing_module, whose result
  # and invocation count are driven through the given agent. Modes:
  #   :error   - hard error (weight 2)
  #   :timeout - timeout-flavored error (weight 1)
  #   :garbage - malformed return (normalized to a hard error by the fan-out)
  #   :ok      - success
  defp with_adapter_mocks(agent, fun) do
    ok_modules = Helper.metric_modules() -- [@failing_module]

    ok_modules
    |> Enum.reduce(Sanbase.Mock.init(), fn module, state ->
      Sanbase.Mock.prepare_mock(state, module, :available_metrics, fn _selector, _opts ->
        {:ok, ["mock_metric_ok"]}
      end)
    end)
    |> Sanbase.Mock.prepare_mock(@failing_module, :available_metrics, fn _selector, _opts ->
      Agent.get_and_update(agent, fn %{mode: mode, calls: calls} = state ->
        result =
          case mode do
            :error -> {:error, "upstream down"}
            :timeout -> {:error, "Timeout exceeded while reading from socket"}
            :garbage -> :boom
            :ok -> {:ok, ["mock_metric_recovered"]}
          end

        {result, %{state | calls: calls + 1}}
      end)
    end)
    |> Sanbase.Mock.run_with_mocks(fun)
  end

  test "trips after 3 consecutive hard errors, skips while open, recovers via a half-open trial",
       %{selector: selector} do
    agent = start_supervised!({Agent, fn -> %{mode: :error, calls: 0} end})

    with_adapter_mocks(agent, fn ->
      # Hard errors weigh 2. Below the trip threshold of 6 the breaker stays
      # CLOSED: the module is re-probed on every call (errors are never cached)
      # and only its metrics are missing from the still-:nocache result.
      assert {:nocache, {:ok, _}} = Metric.available_metrics_for_selector(selector, [])
      assert failure_score(selector) == 2
      assert check(selector) == :closed

      assert {:nocache, {:ok, _}} = Metric.available_metrics_for_selector(selector, [])
      assert failure_score(selector) == 4
      assert check(selector) == :closed
      assert Agent.get(agent, & &1.calls) == 2

      # The 3rd hard error reaches the threshold and trips the breaker OPEN.
      assert {:nocache, {:ok, _}} = Metric.available_metrics_for_selector(selector, [])
      assert failure_score(selector) == 6
      assert {:open, _} = check(selector)
      assert Agent.get(agent, & &1.calls) == 3

      # While open the module is skipped - not re-invoked - even after it
      # recovers upstream.
      Agent.update(agent, &%{&1 | mode: :ok})
      assert {:nocache, {:ok, _}} = Metric.available_metrics_for_selector(selector, [])
      assert Agent.get(agent, & &1.calls) == 3

      # The open window expires (forced instead of waiting out the TTL). The
      # half-open trial probe succeeds, closing the breaker and resetting the
      # score; the full list is returned untagged.
      close(selector)
      assert {:ok, metrics} = Metric.available_metrics_for_selector(selector, [])
      assert "mock_metric_recovered" in metrics
      assert failure_score(selector) == 0
      assert Agent.get(agent, & &1.calls) == 4
    end)
  end

  test "timeout failures weigh less and only trip after 6 in a row", %{selector: selector} do
    agent = start_supervised!({Agent, fn -> %{mode: :timeout, calls: 0} end})

    with_adapter_mocks(agent, fn ->
      # Timeouts weigh 1: five in a row leave the breaker closed and probing.
      for n <- 1..5 do
        assert {:nocache, {:ok, _}} = Metric.available_metrics_for_selector(selector, [])
        assert failure_score(selector) == n
        assert check(selector) == :closed
        assert Agent.get(agent, & &1.calls) == n
      end

      # The 6th reaches the threshold and trips the breaker.
      assert {:nocache, {:ok, _}} = Metric.available_metrics_for_selector(selector, [])
      assert failure_score(selector) == 6
      assert {:open, _} = check(selector)
      assert Agent.get(agent, & &1.calls) == 6
    end)
  end

  test "mixed timeout and error failures accumulate by weight", %{selector: selector} do
    agent = start_supervised!({Agent, fn -> %{mode: :timeout, calls: 0} end})

    with_adapter_mocks(agent, fn ->
      # Two timeouts: score 2, closed.
      assert {:nocache, {:ok, _}} = Metric.available_metrics_for_selector(selector, [])
      assert {:nocache, {:ok, _}} = Metric.available_metrics_for_selector(selector, [])
      assert failure_score(selector) == 2
      assert check(selector) == :closed

      # A hard error: score 4, still closed. A second one reaches 6 and trips.
      Agent.update(agent, &%{&1 | mode: :error})
      assert {:nocache, {:ok, _}} = Metric.available_metrics_for_selector(selector, [])
      assert failure_score(selector) == 4
      assert check(selector) == :closed

      assert {:nocache, {:ok, _}} = Metric.available_metrics_for_selector(selector, [])
      assert failure_score(selector) == 6
      assert {:open, _} = check(selector)
    end)
  end

  test "a success resets the accumulated failure score", %{selector: selector} do
    agent = start_supervised!({Agent, fn -> %{mode: :error, calls: 0} end})

    with_adapter_mocks(agent, fn ->
      # Two hard errors - score 4, still below the threshold.
      assert {:nocache, {:ok, _}} = Metric.available_metrics_for_selector(selector, [])
      assert {:nocache, {:ok, _}} = Metric.available_metrics_for_selector(selector, [])
      assert failure_score(selector) == 4

      # A success clears the score.
      Agent.update(agent, &%{&1 | mode: :ok})
      assert {:ok, _} = Metric.available_metrics_for_selector(selector, [])
      assert failure_score(selector) == 0

      # So a fresh failure starts scoring from its own weight again (the module
      # must be re-probed, so drop its now-cached success first).
      Agent.update(agent, &%{&1 | mode: :error})
      Sanbase.Cache.clear(module_cache_key(selector))
      assert {:nocache, {:ok, _}} = Metric.available_metrics_for_selector(selector, [])
      assert failure_score(selector) == 2
      assert check(selector) == :closed
    end)
  end

  test "a failing module still serves its last-known-good metrics", %{selector: selector} do
    agent = start_supervised!({Agent, fn -> %{mode: :ok, calls: 0} end})

    with_adapter_mocks(agent, fn ->
      # 1st call: the module succeeds; its list is stored as last-known-good.
      assert {:ok, metrics} = Metric.available_metrics_for_selector(selector, [])
      assert "mock_metric_recovered" in metrics
      assert Agent.get(agent, & &1.calls) == 1

      # Now it fails (force a re-probe past the cached success). Even a single
      # closed-state failure serves the stale list rather than dropping it, with
      # the batch tagged :nocache so it keeps retrying.
      Agent.update(agent, &%{&1 | mode: :error})
      Sanbase.Cache.clear(module_cache_key(selector))
      assert {:nocache, {:ok, metrics}} = Metric.available_metrics_for_selector(selector, [])
      assert "mock_metric_recovered" in metrics
      assert check(selector) == :closed
      assert Agent.get(agent, & &1.calls) == 2
    end)
  end

  test "a malformed module return is normalized to an error: never cached, scored once as hard",
       %{selector: selector} do
    agent = start_supervised!({Agent, fn -> %{mode: :garbage, calls: 0} end})

    with_adapter_mocks(agent, fn ->
      # The garbage return is normalized to {:error, {:invalid_result, :boom}}:
      # scored exactly once (weight 2, by the probe - the caller-side pass must
      # skip it) and never written to the module cache.
      assert {:nocache, {:ok, _}} = Metric.available_metrics_for_selector(selector, [])
      assert failure_score(selector) == 2
      assert Sanbase.Cache.get(module_cache_key(selector)) == nil

      # Not cached, so the next call genuinely re-probes and scores again.
      assert {:nocache, {:ok, _}} = Metric.available_metrics_for_selector(selector, [])
      assert failure_score(selector) == 4
      assert Agent.get(agent, & &1.calls) == 2
    end)
  end

  test "when disabled, the breaker never opens and serves no stale list", %{selector: selector} do
    original = Application.get_env(:sanbase, CircuitBreaker)
    Application.put_env(:sanbase, CircuitBreaker, enabled: false)
    on_exit(fn -> restore_env(original) end)

    refute CircuitBreaker.enabled?()

    agent = start_supervised!({Agent, fn -> %{mode: :error, calls: 0} end})

    with_adapter_mocks(agent, fn ->
      # Many consecutive failures never open the breaker: every call re-probes
      # the upstream and the failing module's metrics are simply dropped.
      for n <- 1..5 do
        assert {:nocache, {:ok, metrics}} = Metric.available_metrics_for_selector(selector, [])
        refute "mock_metric_recovered" in metrics
        assert check(selector) == :closed
        assert Agent.get(agent, & &1.calls) == n
      end

      # No breaker state is tracked while disabled.
      assert failure_score(selector) == 0
      assert last_good(selector) == []
    end)
  end

  test "enabled? accepts 1/true in any case as enabled, and anything else as disabled" do
    original = Application.get_env(:sanbase, CircuitBreaker)
    on_exit(fn -> restore_env(original) end)

    for value <- ["1", 1, "true", "True", "TRUE", true] do
      Application.put_env(:sanbase, CircuitBreaker, enabled: value)
      assert CircuitBreaker.enabled?(), "expected #{inspect(value)} to enable the breaker"
    end

    for value <- ["0", 0, "false", "False", "FALSE", false, "yes", "on"] do
      Application.put_env(:sanbase, CircuitBreaker, enabled: value)
      refute CircuitBreaker.enabled?(), "expected #{inspect(value)} to disable the breaker"
    end
  end

  defp restore_env(nil), do: Application.delete_env(:sanbase, CircuitBreaker)
  defp restore_env(value), do: Application.put_env(:sanbase, CircuitBreaker, value)
end
