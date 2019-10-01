defmodule Sanbase.Project.AvailableMetricsTest do
  use SanbaseWeb.ConnCase, async: false

  import Mock
  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  test "get project's available metrics" do
    project = insert(:random_erc20_project)

    with_mock(Sanbase.Clickhouse.Metric, [:passthrough],
      available_slugs: fn -> {:ok, [project.slug]} end
    ) do
      result = get_available_metrics(project)
      %{"data" => %{"projectBySlug" => %{"availableMetrics" => available_metrics}}} = result

      assert available_metrics == Sanbase.Clickhouse.Metric.available_metrics()
    end
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
