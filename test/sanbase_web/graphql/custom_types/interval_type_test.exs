defmodule SanbaseWeb.Graphql.CustomTypes.IntervalTypeTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers

  test "invalid interval" do
    query = """
    {
      getMetric(metric: "daily_active_addresses"){
        timeseriesData(slug: "santiment"
        from: "2019-01-01T00:00:00Z"
        to: "2019-02-01T00:00:00Z"
        interval: "10hour") {
          datetime
          value
        }
      }
    }
    """

    result =
      build_conn()
      |> post("/graphql", query_skeleton(query))
      |> json_response(200)

    assert result == %{
             "errors" => [
               %{
                 "locations" => [%{"column" => 5, "line" => 6}],
                 "message" => ~s(Argument "interval" has invalid value "10hour".)
               }
             ]
           }
  end
end
