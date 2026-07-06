defmodule Sanbase.Metric.AvailableMetricsCooldownTest do
  # Mocks (meck) patch modules globally, so this file cannot run async. DataCase
  # (not plain ExUnit.Case) because the experimental-metrics filter inside
  # available_metrics_for_selector/2 queries the metric registry in Postgres,
  # and its shared sandbox checkout also covers the parallel Task processes.
  use Sanbase.DataCase, async: false

  alias Sanbase.Metric
  alias Sanbase.Metric.Helper

  @moduletag capture_log: true

  @failing_module Sanbase.Twitter.MetricAdapter

  setup do
    # Unique slug per test so the per-module and cooldown cache keys (both keyed
    # by selector) never collide across tests or repeated runs.
    slug = "cooldown-test-#{System.unique_integer([:positive])}"
    {:ok, selector: %{slug: slug}}
  end

  # Mirrors module_cooldown_key/4 in Sanbase.Metric (private there).
  defp cooldown_key(selector) do
    {Sanbase.Metric, :available_metrics_module_cooldown, @failing_module, selector, "released",
     nil}
    |> Sanbase.Cache.hash()
  end

  # Mock every metric module: all succeed except @failing_module, whose result
  # and invocation count are driven through the given agent.
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
            :fail -> {:error, "upstream down"}
            :ok -> {:ok, ["mock_metric_recovered"]}
          end

        {result, %{state | calls: calls + 1}}
      end)
    end)
    |> Sanbase.Mock.run_with_mocks(fun)
  end

  test "a failing module goes into cooldown, is skipped, and recovers once the marker clears",
       %{selector: selector} do
    agent = start_supervised!({Agent, fn -> %{mode: :fail, calls: 0} end})

    with_adapter_mocks(agent, fn ->
      # 1st call: the module is genuinely invoked and fails. The result is a
      # partial list tagged :nocache and a cooldown marker is written.
      assert {:nocache, {:ok, metrics}} = Metric.available_metrics_for_selector(selector, [])
      assert "mock_metric_ok" in metrics
      refute "mock_metric_recovered" in metrics
      assert Agent.get(agent, & &1.calls) == 1
      assert {:module_failure_cooldown, _} = Sanbase.Cache.get(cooldown_key(selector))

      # 2nd call within the cooldown: the module is NOT re-invoked; the result
      # stays partial + :nocache.
      assert {:nocache, {:ok, _}} = Metric.available_metrics_for_selector(selector, [])
      assert Agent.get(agent, & &1.calls) == 1

      # The upstream recovers, but the marker still short-circuits the call.
      Agent.update(agent, &%{&1 | mode: :ok})
      assert {:nocache, {:ok, _}} = Metric.available_metrics_for_selector(selector, [])
      assert Agent.get(agent, & &1.calls) == 1

      # Cooldown expires (cleared manually instead of waiting out the TTL). The
      # module is re-invoked, succeeds, and the full list is returned untagged.
      Sanbase.Cache.clear(cooldown_key(selector))

      assert {:ok, metrics} = Metric.available_metrics_for_selector(selector, [])
      assert "mock_metric_recovered" in metrics
      assert Agent.get(agent, & &1.calls) == 2
    end)
  end
end
