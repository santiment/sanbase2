defmodule SanbaseWeb.Graphql.SharedAccessTokenAuthApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    pro_user = insert(:user)
    insert(:subscription_pro_sanbase, user: pro_user, stripe_id: "test stripe id")
    pro_conn = setup_jwt_auth(build_conn(), pro_user)

    p1 = insert(:random_project, slug: "some_slug_1", ticker: "SS1")
    p2 = insert(:random_project, slug: "some_slug_2", ticker: "SS2")

    _ = insert(:metric_postgres, name: "defi_total_value_locked_usd")
    _ = insert(:metric_postgres, name: "daily_active_addresses")
    _ = insert(:metric_postgres, name: "mvrv_usd")

    chart_configuration =
      insert(:chart_configuration,
        user: pro_user,
        project: p1,
        is_public: true,
        metrics: [
          "defi_total_value_locked_usd",
          "some_slug_2-CC-SS2-CC-cexes_to_dex_traders_flow",
          "holders_distribution_combined_balance_1_to_10__MM__holders_distribution_combined_balance_10_to_100"
        ]
      )

    user = insert(:user)
    conn = build_conn()

    anon_conn = build_conn()

    %{
      pro_user: pro_user,
      pro_conn: pro_conn,
      user: user,
      conn: conn,
      anon_conn: anon_conn,
      chart_configuration: chart_configuration,
      config_project: p1,
      project: p2
    }
  end

  test "check access to metrics", context do
    token_uuid =
      generate_chart_configuration_shared_access_token(
        context.pro_conn,
        context.chart_configuration.id
      )
      |> get_in(["data", "generateChartConfigurationSharedAccessToken", "uuid"])

    from = ~U[2015-01-01 00:00:00Z]
    to = ~U[2016-10-01 00:00:00Z]
    result = {:ok, [%{datetime: from, value: 5}, %{datetime: to, value: 10}]}

    Sanbase.Mock.prepare_mock2(&Sanbase.Metric.timeseries_data/6, result)
    |> Sanbase.Mock.run_with_mocks(fn ->
      expected_metric_result = %{
        "data" => %{
          "getMetric" => %{
            "timeseriesData" => [
              %{"datetime" => DateTime.to_iso8601(from), "value" => 5.0},
              %{"datetime" => DateTime.to_iso8601(to), "value" => 10.0}
            ]
          }
        }
      }

      conn = context.conn
      slug = context.config_project.slug
      p = insert(:random_project)

      # Fails because the context does not have the shared access token
      # and the user does not have any subscription plan
      assert %{"errors" => [_]} =
               get_metric(conn, "defi_total_value_locked_usd", slug, from, to, "1d")

      assert %{"errors" => [_]} = get_metric(conn, "nvt", slug, from, to, "1d")

      assert %{"errors" => [_]} = get_metric(conn, "mvrv_usd", slug, from, to, "1d")

      # Add the shared access token to the connection. The calls that use the
      # metrics and slugs in the chart layout will suceed.
      conn =
        context.conn
        |> Plug.Conn.put_req_header(
          "x-sharedaccess-authorization",
          "SharedAccessToken #{token_uuid}"
        )

      # success calls
      assert get_metric(conn, "defi_total_value_locked_usd", slug, from, to, "1d") ==
               expected_metric_result

      assert get_metric(conn, "nvt", slug, from, to, "1d") ==
               expected_metric_result

      assert get_metric(conn, "mvrv_usd", slug, from, to, "1d") ==
               expected_metric_result

      # Fail calls with the token

      # This slug is not in the chart layout
      assert %{"errors" => [_]} =
               get_metric(conn, "defi_total_value_locked_usd", p.slug, from, to, "1d")

      # The metric is not in the chart layout
      assert %{"errors" => [_]} =
               get_metric(conn, "dex_to_cexes_flow_change_30d", slug, from, to, "1d")
    end)
  end

  test "cannot create token for private layout", context do
    chart_config = insert(:chart_configuration, user: context.pro_user, is_public: false)

    error =
      generate_chart_configuration_shared_access_token(context.pro_conn, chart_config.id)
      |> get_in(["errors", Access.at(0), "message"])

    assert error == "Shared Access Token can be created only for a public chart configuration."
  end

  test "cannot create token for other's layout", context do
    chart_config = insert(:chart_configuration, user: context.user, is_public: false)

    error =
      generate_chart_configuration_shared_access_token(context.pro_conn, chart_config.id)
      |> get_in(["errors", Access.at(0), "message"])

    assert error == "Chart configuration with id #{chart_config.id} is private."
  end

  defp get_metric(conn, metric, slug, from, to, interval) do
    query = """
      {
        getMetric(metric: "#{metric}"){
          timeseriesData(
            slug: "#{slug}", from: "#{from}", to: "#{to}", interval: "#{interval}"){
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

  defp generate_chart_configuration_shared_access_token(conn, chart_configuration_id) do
    mutation = """
    mutation{
      generateChartConfigurationSharedAccessToken(
        chartConfigurationId: #{chart_configuration_id}){
          uuid
      }
    }
    """

    conn
    |> post("/graphql", mutation_skeleton(mutation))
    |> json_response(200)
  end
end
