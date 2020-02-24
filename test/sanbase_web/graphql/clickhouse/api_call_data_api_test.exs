defmodule SanbaseWeb.Graphql.ApiCallDataApiTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  setup do
    user = insert(:user)
    insert(:subscription_premium, user: user)
    conn = setup_jwt_auth(build_conn(), user)
    {:ok, conn: conn}
  end

  test "export get_metric api calls with the metric as argument", context do
    %{conn: conn} = context

    Sanbase.Mock.prepare_mock2(&Sanbase.Metric.timeseries_data/6, {:ok, []})
    |> Sanbase.Mock.run_with_mocks(fn ->
      from = ~U[2019-01-05 00:00:00Z]
      to = ~U[2019-01-06 00:00:00Z]

      Sanbase.InMemoryKafka.Producer.clear_state()
      get_metric(conn, "price_usd", "santiment", from, to, "1d")
      get_metric(conn, "nvt", "santiment", from, to, "1d")
      get_metric(conn, "daily_active_addresses", "santiment", from, to, "1d")

      # force the sending
      Sanbase.KafkaExporter.flush(:api_call_exporter)

      %{"sanbase_api_call_data" => api_calls} = Sanbase.InMemoryKafka.Producer.get_state()

      api_calls_queries =
        Enum.map(api_calls, fn {_, data} -> Jason.decode!(data) |> Map.get("query") end)

      # There could be some test that exported api calls data and that happens async
      # so something could happend even after the `clear_state` is called
      assert length(api_calls_queries) >= 3
      assert "getMetric|nvt" in api_calls_queries
      assert "getMetric|price_usd" in api_calls_queries
      assert "getMetric|daily_active_addresses" in api_calls_queries
    end)
  end

  defp get_metric(conn, metric, slug, from, to, interval) do
    query = """
    {
      get_metric(metric: "#{metric}") {
        timeseriesData(slug: "#{slug}", from: "#{from}", to: "#{to}", interval: "#{interval}"){
          datetime
          value
        }
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end
end
