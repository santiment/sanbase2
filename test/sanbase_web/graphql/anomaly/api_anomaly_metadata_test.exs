defmodule SanbaseWeb.Graphql.Clickhouse.ApiAnomalyMetadataTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory, only: [rand_str: 0]
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Anomaly

  test "returns data for all available anomaly", %{conn: conn} do
    anomalies = Anomaly.available_anomalies()
    aggregations = Anomaly.available_aggregations()

    aggregations =
      aggregations |> Enum.map(fn aggr -> aggr |> Atom.to_string() |> String.upcase() end)

    for anomaly <- anomalies do
      %{"data" => %{"getAnomaly" => %{"metadata" => metadata}}} =
        get_anomaly_metadata(conn, anomaly)

      assert metadata["anomaly"] == anomaly

      assert match?(
               %{"anomaly" => _, "defaultAggregation" => _, "minInterval" => _, "dataType" => _},
               metadata
             )

      assert metadata["defaultAggregation"] in aggregations
      assert metadata["minInterval"] in ["1d"]
      assert metadata["dataType"] in ["TIMESERIES"]
      assert length(metadata["availableAggregations"]) > 0
    end
  end

  test "returns error for unavailable anomaly", %{conn: conn} do
    rand_anomalies = Enum.map(1..100, fn _ -> rand_str() end)
    rand_anomalies = rand_anomalies -- Anomaly.available_anomalies()

    # Do not mock the `histogram_data` function because it's the one that rejects
    for anomaly <- rand_anomalies do
      %{
        "errors" => [
          %{"message" => error_message}
        ]
      } = get_anomaly_metadata(conn, anomaly)

      assert error_message == "The anomaly '#{anomaly}' is not supported or is mistyped."
    end
  end

  defp get_anomaly_metadata(conn, anomaly) do
    query = """
    {
      getAnomaly(anomaly: "#{anomaly}"){
        metadata{
          minInterval
          defaultAggregation
          availableAggregations
          dataType
          anomaly
        }
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end
end
