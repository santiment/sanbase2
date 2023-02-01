defmodule SanbaseWeb.Graphql.Clickhouse.ApiSignalMetadataTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory, only: [rand_str: 0]
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Signal

  test "returns data for all available signal", %{conn: conn} do
    signals = Signal.available_signals()
    aggregations = Signal.available_aggregations()

    aggregations =
      aggregations |> Enum.map(fn aggr -> aggr |> Atom.to_string() |> String.upcase() end)

    for signal <- signals do
      %{"data" => %{"getSignal" => %{"metadata" => metadata}}} = get_signal_metadata(conn, signal)

      assert metadata["signal"] == signal

      assert match?(
               %{"signal" => _, "defaultAggregation" => _, "minInterval" => _, "dataType" => _},
               metadata
             )

      assert metadata["defaultAggregation"] in aggregations
      assert metadata["minInterval"] in ["5m"]
      assert metadata["dataType"] in ["TIMESERIES"]
      assert length(metadata["availableAggregations"]) > 0
    end
  end

  test "returns error for unavailable signal", %{conn: conn} do
    rand_signals = Enum.map(1..100, fn _ -> rand_str() end)
    rand_signals = rand_signals -- Signal.available_signals()

    # Do not mock the `histogram_data` function because it's the one that rejects
    for signal <- rand_signals do
      %{
        "errors" => [
          %{"message" => error_message}
        ]
      } = get_signal_metadata(conn, signal)

      assert error_message == "The signal '#{signal}' is not supported or is mistyped."
    end
  end

  defp get_signal_metadata(conn, signal) do
    query = """
    {
      getSignal(signal: "#{signal}"){
        metadata{
          minInterval
          defaultAggregation
          availableAggregations
          dataType
          signal
        }
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end
end
