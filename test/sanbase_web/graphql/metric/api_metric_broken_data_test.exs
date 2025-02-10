defmodule SanbaseWeb.Graphql.ApiMetricBrokenDataTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  test "returns broken data", %{conn: conn} do
    github_metrics = Sanbase.Clickhouse.Github.MetricAdapter.available_metrics()
    project = insert(:random_project)

    for metric <- github_metrics do
      # This overlaps with a known broken interval
      broken_data =
        get(conn, metric, project.slug, ~U[2021-01-10 00:00:00Z], ~U[2021-11-11 00:00:00Z])

      assert broken_data == [
               %{
                 "actionsToFix" => "The github events are not possible to be refetched so the gap cannot be filled.",
                 "from" => "2021-10-07T00:00:00Z",
                 "notes" =>
                   "Due to missing github data the development activity related metrics are lower than they should be.",
                 "to" => "2021-11-01T00:00:00Z",
                 "what" => "Github events are partially or fully missing in the specified range.",
                 "why" => "Third-party data provider outage."
               }
             ]
    end

    not_broken_metrics =
      (Sanbase.Metric.available_metrics() -- github_metrics) |> Enum.shuffle() |> Enum.take(100)

    for metric <- not_broken_metrics do
      broken_data =
        get(conn, metric, project.slug, ~U[2021-01-10 00:00:00Z], ~U[2021-11-11 00:00:00Z])

      assert broken_data == []
    end
  end

  defp get(conn, metric, slug, from, to) do
    selector = %{slug: slug}
    selector = extend_selector_with_required_fields(metric, selector)

    query = """
    {
      getMetric(metric: "#{metric}"){
        brokenData(selector: #{map_to_input_object_str(selector)} from: "#{from}" to: "#{to}"){
          from
          to
          what
          why
          notes
          actionsToFix
        }
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
    |> get_in(["data", "getMetric", "brokenData"])
  end
end
