defmodule Sanbase.Project.AvailableMetricsTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    # Re-enable the RC branch in `ProjectMetricsResolver` for this file only so
    # the resolver ↔ RehydratingCache integration is exercised end-to-end.
    # `on_exit` restores the test-default (false) so later files stay isolated.
    Application.put_env(:sanbase, :use_rehydrating_cache, true)
    on_exit(fn -> Application.put_env(:sanbase, :use_rehydrating_cache, false) end)

    # Per-test RC supervisor. No manual `stop_supervised` needed: ExUnit tracks
    # everything started via `start_supervised!/1` under a test-owned supervisor
    # and shuts them down in reverse start order when the test exits (pass, fail,
    # or crash). That tears down the RC GenServer, its ConCache store, and the
    # Task.Supervisor — so no closure leaks into later tests. `async: false` above
    # is required because the RC supervisor registers fixed atoms
    # (e.g. `:__rehydrating_cache__`), which can't coexist across parallel tests.
    start_supervised!(Sanbase.Cache.RehydratingCache.Supervisor)

    :ok
  end

  test "get project's available metrics" do
    project = insert(:random_erc20_project)
    available_metrics = Sanbase.Metric.available_metrics()

    metrics =
      available_metrics |> Enum.shuffle() |> Enum.take(Enum.random(1..length(available_metrics)))

    Sanbase.Mock.prepare_mock2(&Sanbase.Metric.available_metrics_for_selector/2, {:ok, metrics})
    |> Sanbase.Mock.run_with_mocks(fn ->
      result = get_available_metrics(project)
      %{"data" => %{"projectBySlug" => %{"availableMetrics" => available_metrics}}} = result

      assert available_metrics == metrics
    end)
  end

  defp get_available_metrics(project) do
    query = """
    {
      projectBySlug(slug: "#{project.slug}"){
        availableMetrics
      }
    }
    """

    build_conn()
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end
end
