defmodule SanbaseWeb.Graphql.PriceVolumeDiffApiTest do
  use SanbaseWeb.ConnCase, async: false
  use Mockery

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers
  import ExUnit.CaptureLog

  setup do
    project = insert(:project, %{name: "Santiment", ticker: "SAN", coinmarketcap_id: "santiment"})

    [
      project: project,
      datetime1: DateTime.from_naive!(~N[2017-05-13 21:45:00], "Etc/UTC"),
      datetime2: DateTime.from_naive!(~N[2017-05-13 21:55:00], "Etc/UTC")
    ]
  end

  test "tech_indicators returns correct result", context do
    mock(
      HTTPoison,
      :get,
      {:ok,
       %HTTPoison.Response{
         body:
           "[{\"price_volume_diff\": 0.0, \"price_change\": 0.04862261825993345, \"volume_change\": 0.030695260272520467, \"timestamp\": 1516406400}, {\"price_volume_diff\": -0.014954423076923185, \"price_change\": 0.04862261825993345, \"volume_change\": 0.030695260272520467, \"timestamp\": 1516492800}, {\"price_volume_diff\": -0.02373337292856359, \"price_change\": 0.04862261825993345, \"volume_change\": 0.030695260272520467, \"timestamp\": 1516579200}, {\"price_volume_diff\": -0.030529013702074614, \"price_change\": 0.04862261825993345, \"volume_change\": 0.030695260272520467, \"timestamp\": 1516665600}, {\"price_volume_diff\": -0.0239400614928722, \"price_change\": 0.04862261825993345, \"volume_change\": 0.030695260272520467, \"timestamp\": 1516752000}]",
         status_code: 200
       }}
    )

    query = price_volume_diff_query(context)

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "priceVolumeDiff"))
      |> json_response(200)

    assert result == %{
             "data" => %{
               "priceVolumeDiff" => [
                 %{
                   "datetime" => "2018-01-20T00:00:00Z",
                   "priceChange" => 0.04862261825993345,
                   "priceVolumeDiff" => 0.0,
                   "volumeChange" => 0.030695260272520467
                 },
                 %{
                   "datetime" => "2018-01-21T00:00:00Z",
                   "priceChange" => 0.04862261825993345,
                   "priceVolumeDiff" => -0.014954423076923185,
                   "volumeChange" => 0.030695260272520467
                 },
                 %{
                   "datetime" => "2018-01-22T00:00:00Z",
                   "priceChange" => 0.04862261825993345,
                   "priceVolumeDiff" => -0.02373337292856359,
                   "volumeChange" => 0.030695260272520467
                 },
                 %{
                   "datetime" => "2018-01-23T00:00:00Z",
                   "priceChange" => 0.04862261825993345,
                   "priceVolumeDiff" => -0.030529013702074614,
                   "volumeChange" => 0.030695260272520467
                 },
                 %{
                   "datetime" => "2018-01-24T00:00:00Z",
                   "priceChange" => 0.04862261825993345,
                   "priceVolumeDiff" => -0.0239400614928722,
                   "volumeChange" => 0.030695260272520467
                 }
               ]
             }
           }
  end

  test "tech_indicators returns empty result", context do
    mock(
      HTTPoison,
      :get,
      {:ok,
       %HTTPoison.Response{
         body: "[]",
         status_code: 200
       }}
    )

    query = price_volume_diff_query(context)

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "priceVolumeDiff"))
      |> json_response(200)

    assert result == %{
             "data" => %{
               "priceVolumeDiff" => []
             }
           }
  end

  test "tech_indicators returns error", context do
    mock(
      HTTPoison,
      :get,
      {:ok,
       %HTTPoison.Response{
         body: "Internal Server Error",
         status_code: 500
       }}
    )

    query = price_volume_diff_query(context)

    assert capture_log(fn ->
             result =
               context.conn
               |> post("/graphql", query_skeleton(query, "priceVolumeDiff"))
               |> json_response(200)

             assert result["data"] == %{"priceVolumeDiff" => nil}
             error = result["errors"] |> List.first()
             assert error["message"] =~ "Error executing query. See logs for details"
           end) =~
             "Error status 500 fetching price-volume diff for project with coinmarketcap_id santiment: Internal Server Error"
  end

  # Private functions

  defp price_volume_diff_query(context) do
    """
    {
      priceVolumeDiff(
        slug: "#{context.project.coinmarketcap_id}"
        currency: "USD"
        from: "#{context.datetime1}"
        to: "#{context.datetime2}") {
          datetime
          priceVolumeDiff
          priceChange
          volumeChange
        }
    }
    """
  end
end
