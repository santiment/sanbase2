defmodule SanbaseWeb.Graphql.ApiCallDataApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Clickhouse.MetricAdapter
  alias Sanbase.InMemoryKafka.Producer

  setup do
    user = insert(:user)
    project = insert(:random_project)
    project2 = insert(:random_project)
    insert(:subscription_pro_sanbase, user: user)
    conn = setup_jwt_auth(build_conn(), user)
    %{conn: conn, project: project, project2: project2}
  end

  @tag :skip
  # TODO: fix this test. On CI it timeouts, locally also fails but with different error
  test "export get_metric api calls with the metric and slug as arguments", context do
    %{conn: conn, project: %{slug: slug}, project2: %{slug: slug2}} = context

    (&MetricAdapter.timeseries_data/6)
    |> Sanbase.Mock.prepare_mock2({:ok, []})
    |> Sanbase.Mock.prepare_mock2(
      &MetricAdapter.timeseries_data_per_slug/6,
      {:ok, []}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      from = ~U[2019-01-05 00:00:00Z]
      to = ~U[2019-01-06 00:00:00Z]

      Producer.clear_state()
      get_metric(conn, "mvrv_usd", slug, from, to, "1d")
      get_metric(conn, "nvt", slug, from, to, "1d")
      get_metric(conn, "daily_active_addresses", slug, from, to, "1d")

      get_metric_timeseries_data_per_slug(conn, "nvt", [slug, slug2], from, to, "1d")
      get_metric_timeseries_data_per_slug(conn, "mvrv_usd", [slug, slug2], from, to, "1d")

      # force the sending
      Sanbase.KafkaExporter.flush(:api_call_exporter)

      %{"sanbase_api_call_data" => api_calls} = Producer.get_state()

      api_calls =
        Enum.map(api_calls, fn {_, data} ->
          data = Jason.decode!(data)
          %{query: data["query"], selector: data["selector"]}
        end)

      # There could be some test that exported api calls data and that happens async
      # so something could happend even after the `clear_state` is called
      assert length(api_calls) >= 5
      slug_selector = Jason.encode!([%{slug: slug}])
      slugs_selector = Jason.encode!([%{slugs: [slug, slug2]}])

      assert %{
               query: "getMetric|daily_active_addresses",
               selector: slug_selector
             } in api_calls

      assert %{
               query: "getMetric|nvt",
               selector: slug_selector
             } in api_calls

      assert %{
               query: "getMetric|mvrv_usd",
               selector: slug_selector
             } in api_calls

      assert %{
               query: "getMetric|nvt",
               selector: slugs_selector
             } in api_calls

      assert %{
               query: "getMetric|mvrv_usd",
               selector: slugs_selector
             } in api_calls
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

  defp get_metric_timeseries_data_per_slug(conn, metric, slugs, from, to, interval) do
    slugs_str = Enum.map_join(slugs, ", ", &~s|"#{&1}"|)

    query = """
    {
      get_metric(metric: "#{metric}") {
        timeseriesDataPerSlug(selector: {slugs: [#{slugs_str}]}, from: "#{from}", to: "#{to}", interval: "#{interval}"){
          datetime
          data{
            slug
            value
          }
        }
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end
end
