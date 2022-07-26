defmodule Sanbase.Project.AvailableMetricsTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  test "get project's available metrics" do
    project = insert(:random_erc20_project)
    available_metrics = Sanbase.Metric.available_metrics()

    metrics =
      available_metrics |> Enum.shuffle() |> Enum.take(Enum.random(1..length(available_metrics)))

    Sanbase.Mock.prepare_mock2(&Sanbase.Metric.available_metrics_for_selector/1, {:ok, metrics})
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
