defmodule SanbaseWeb.Graphql.ApiCallDataApiTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  @moduletag skip: true
  setup_all do
    Application.put_env(SanbaseWeb.Graphql.AbsintheBeforeSend, :api_call_exporting_enabled, true)

    on_exit(fn ->
      Application.delete_env(SanbaseWeb.Graphql.AbsintheBeforeSend, :api_call_exporting_enabled)
    end)
  end

  setup do
    # The test suite is not asynchronous. Wait a little before cleaning the state
    # so all other tests finish exporting their data and we can clean it.
    Process.sleep(100)
    Sanbase.InMemoryKafka.Producer.clear_state()

    user = insert(:user)
    project = insert(:random_project)
    project2 = insert(:random_project)
    insert(:subscription_business_max_monthly, user: user)

    {:ok, apikey} = Sanbase.Accounts.Apikey.generate_apikey(user)
    conn = setup_apikey_auth(build_conn(), apikey)

    %{
      conn: conn,
      apikey: apikey,
      project: project,
      project2: project2,
      from: ~U[2019-01-05 00:00:00Z],
      to: ~U[2019-01-06 00:00:00Z]
    }
  end

  test "export get_metric api calls with the metric and slug as arguments", context do
    %{conn: conn, apikey: apikey, project: %{slug: slug}, project2: %{slug: slug2}} = context
    %{from: from, to: to} = context

    Sanbase.Mock.prepare_mock2(&Sanbase.Clickhouse.MetricAdapter.timeseries_data/6, {:ok, []})
    |> Sanbase.Mock.prepare_mock2(
      &Sanbase.Clickhouse.MetricAdapter.timeseries_data_per_slug/6,
      {:ok, []}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      get_metric(conn, "mvrv_usd", slug, from, to, "1d")
      get_metric(conn, "nvt", slug, from, to, "1d")
      get_metric(conn, "daily_active_addresses", slug, from, to, "1d")

      get_metric_timeseries_data_per_slug(conn, "nvt", [slug, slug2], from, to, "1d")
      get_metric_timeseries_data_per_slug(conn, "mvrv_usd", [slug, slug2], from, to, "1d")

      # force the sending
      Sanbase.KafkaExporter.flush(:api_call_exporter)

      %{"sanbase_api_call_data" => api_calls} = Sanbase.InMemoryKafka.Producer.get_state()

      api_calls =
        Enum.map(api_calls, fn {_, data} ->
          data = Jason.decode!(data)

          %{
            query: data["query"],
            selector: data["selector"],
            api_token: data["api_token"],
            auth_method: data["auth_method"]
          }
        end)

      # There could be some test that exported api calls data and that happens async
      # so something could happend even after the `clear_state` is called
      assert length(api_calls) >= 5
      slug_selector = [%{slug: slug}] |> Jason.encode!()
      slugs_selector = [%{slugs: [slug, slug2]}] |> Jason.encode!()

      api_token = String.split(apikey, "_") |> hd()

      assert %{
               query: "getMetric|daily_active_addresses",
               selector: slug_selector,
               auth_method: "apikey",
               api_token: api_token
             } in api_calls

      assert %{
               query: "getMetric|nvt",
               selector: slug_selector,
               auth_method: "apikey",
               api_token: api_token
             } in api_calls

      assert %{
               query: "getMetric|mvrv_usd",
               selector: slug_selector,
               auth_method: "apikey",
               api_token: api_token
             } in api_calls

      assert %{
               query: "getMetric|nvt",
               selector: slugs_selector,
               auth_method: "apikey",
               api_token: api_token
             } in api_calls

      assert %{
               query: "getMetric|mvrv_usd",
               selector: slugs_selector,
               auth_method: "apikey",
               api_token: api_token
             } in api_calls
    end)
  end

  test "nothing is exported when query returns error due to argument error", context do
    %{conn: conn, project: %{slug: slug}} = context
    %{from: from, to: to} = context

    Sanbase.Mock.prepare_mock2(&Sanbase.Clickhouse.MetricAdapter.timeseries_data/6, {:ok, []})
    |> Sanbase.Mock.prepare_mock2(
      &Sanbase.Clickhouse.MetricAdapter.timeseries_data_per_slug/6,
      {:ok, []}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      # One successful
      get_metric(conn, "mvrv_usd", slug, from, to, "1d")

      # And a few failed
      get_metric(conn, "mvrv_usds", slug, from, to, "1d")
      get_metric(conn, "nvts", slug, from, to, "1d")

      # force the sending
      Sanbase.KafkaExporter.flush(:api_call_exporter)

      %{"sanbase_api_call_data" => api_calls} = Sanbase.InMemoryKafka.Producer.get_state()

      api_calls =
        Enum.map(api_calls, fn {_, data} ->
          data = Jason.decode!(data)

          %{query: data["query"]}
        end)

      # Only the successful one is exported and counted
      assert assert api_calls == [%{query: "getMetric|mvrv_usd"}]
    end)
  end

  test "nothing is exported when query returns error due to graphql error", context do
    %{conn: conn, project: %{slug: slug}} = context
    %{from: from, to: to} = context

    Sanbase.Mock.prepare_mock2(&Sanbase.Clickhouse.MetricAdapter.timeseries_data/6, {:ok, []})
    |> Sanbase.Mock.prepare_mock2(
      &Sanbase.Clickhouse.MetricAdapter.timeseries_data_per_slug/6,
      {:ok, []}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      # One successful
      get_metric(conn, "mvrv_usd", slug, from, to, "1d")

      # And a failed due to typo in query name
      query = """
      {
        getMMMMMetric(metric: "nvt") {
          timeseriesData(slug: "#{slug}", from: "#{from}", to: "#{to}", interval: "1d"){
            datetime
            value
          }
        }
      }
      """

      conn
      |> post("/graphql", query_skeleton(query))
      |> json_response(200)

      # force the sending
      Sanbase.KafkaExporter.flush(:api_call_exporter)

      %{"sanbase_api_call_data" => api_calls} = Sanbase.InMemoryKafka.Producer.get_state()

      api_calls =
        Enum.map(api_calls, fn {_, data} ->
          data = Jason.decode!(data)

          %{query: data["query"]}
        end)

      # Only the successful one is exported and counted
      assert assert api_calls == [%{query: "getMetric|mvrv_usd"}]
    end)
  end

  test "only some queries return data - export only successful api calls", context do
    %{conn: conn, project: %{slug: slug}} = context
    %{from: from, to: to} = context

    Sanbase.Mock.prepare_mock2(&Sanbase.Clickhouse.MetricAdapter.timeseries_data/6, {:ok, []})
    |> Sanbase.Mock.run_with_mocks(fn ->
      query = """
      {

        willSucceed: getMetric(metric: "mvrv_usd") {
          timeseriesDataJson(slug: "#{slug}", from: "#{from}", to: "#{to}", interval: "1d")
        }

        willFailUnsupprotedSlug: getMetric(metric: "nvt") {
          timeseriesDataJson(slug: "some_unsupported_slug", from: "#{from}", to: "#{to}", interval: "1d")
        }
      }
      """

      conn
      |> post("/graphql", query_skeleton(query))
      |> json_response(200)

      # force the sending
      Sanbase.KafkaExporter.flush(:api_call_exporter)

      %{"sanbase_api_call_data" => api_calls} = Sanbase.InMemoryKafka.Producer.get_state()

      api_calls =
        Enum.map(api_calls, fn {_, data} ->
          data = Jason.decode!(data)

          %{query: data["query"]}
        end)

      # Only the successful one is exported and counted
      assert api_calls == [%{query: "getMetric|mvrv_usd"}]
    end)
  end

  test "no queries return due to critical error in one of them -- nothing is exported", context do
    %{conn: conn, project: %{slug: slug}} = context
    %{from: from, to: to} = context

    Sanbase.Mock.prepare_mock2(&Sanbase.Clickhouse.MetricAdapter.timeseries_data/6, {:ok, []})
    |> Sanbase.Mock.run_with_mocks(fn ->
      query = """
      {

        willSucceedIfAlone: getMetric(metric: "mvrv_usd") {
          timeseriesDataJson(slug: "#{slug}", from: "#{from}", to: "#{to}", interval: "1d")
        }

        willCrashTheWholeDocumentDueToAggregation: getMetric(metric: "nvt") {
          timeseriesDataJson(slug: "some_unsupported_slug", from: "#{from}", to: "#{to}", interval: "1d", aggregation: INVALID_AGGR)
        }
      }
      """

      conn
      |> post("/graphql", query_skeleton(query))
      |> json_response(200)

      # force the sending
      Sanbase.KafkaExporter.flush(:api_call_exporter)

      state = Sanbase.InMemoryKafka.Producer.get_state()
      api_calls = Map.get(state, "sanbase_api_call_data", %{})
      assert Enum.empty?(api_calls)
    end)
  end

  defp get_metric(conn, metric, slug, from, to, interval) do
    # Intentionally one query is defined as get_metric and the other as getMetric
    # so casing unification is tested
    query = """
    {
      get_metric(metric: "#{metric}") {
        timeseriesDataJson(slug: "#{slug}", from: "#{from}", to: "#{to}", interval: "#{interval}")      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end

  defp get_metric_timeseries_data_per_slug(conn, metric, slugs, from, to, interval) do
    slugs_str = Enum.map(slugs, &~s|"#{&1}"|) |> Enum.join(", ")

    query = """
    {
      getMetric(metric: "#{metric}") {
        timeseriesDataPerSlugJson(selector: {slugs: [#{slugs_str}]}, from: "#{from}", to: "#{to}", interval: "#{interval}")
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end
end
