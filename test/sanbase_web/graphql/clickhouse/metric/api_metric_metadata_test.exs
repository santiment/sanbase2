defmodule SanbaseWeb.Graphql.Clickhouse.ApiMetricMetadataTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Clickhouse.Metric

  test "returns data for all available metric", %{conn: conn} do
    {:ok, metrics} = Metric.available_metrics()
    {:ok, aggregations} = Metric.available_aggregations()

    aggregations =
      aggregations |> Enum.map(fn aggr -> aggr |> Atom.to_string() |> String.upcase() end)

    for metric <- metrics do
      %{"data" => %{"getMetric" => %{"metadata" => metadata}}} = fetch_metadata(conn, metric)
      assert match?(%{"defaultAggregation" => _, "minInterval" => _}, metadata)
      assert metadata["defaultAggregation"] in aggregations
      assert metadata["minInterval"] in ["1d", "5m"]
    end
  end

  defp fetch_metadata(conn, metric) do
    query = """
    {
      getMetric(metric: "#{metric}"){
        metadata{
          minInterval
          defaultAggregation
        }
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end
end
