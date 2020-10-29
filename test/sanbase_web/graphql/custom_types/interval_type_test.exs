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

    err_msg = execute_query_with_error(query, "getMetric")
    assert err_msg == "Argument \"interval\" has invalid value \"10hour\"."
  end
end
