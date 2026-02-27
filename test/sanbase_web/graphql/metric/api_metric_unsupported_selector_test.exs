defmodule SanbaseWeb.Graphql.ApiMetricUnsupportedSelectorTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    %{user: user} =
      insert(:subscription_pro_sanbase, user: insert(:user, metric_access_level: "alpha"))

    project = insert(:random_project)
    conn = setup_jwt_auth(build_conn(), user)

    [
      conn: conn,
      slug: project.slug,
      from: ~U[2019-01-01 00:00:00Z],
      to: ~U[2019-01-02 00:00:00Z],
      interval: "1d"
    ]
  end

  describe "timeseries_data with unsupported selector" do
    @tag capture_log: true
    test "returns proper error for clickhouse metric with organization selector", context do
      # `organization` is a valid GraphQL selector field but is not supported by
      # the ClickHouse MetricAdapter (it requires slug, address, or contractAddress)
      error_msg =
        get_timeseries_error(context, "daily_active_addresses", %{organization: "santiment"})

      assert error_msg =~ "The provided selector"
      assert error_msg =~ "is not supported"
    end

    @tag capture_log: true
    test "returns proper error for github metric with text selector", context do
      # `text` is a valid GraphQL selector field but is not supported by
      # the Github MetricAdapter (it requires slug, organization, or organizations)
      error_msg = get_timeseries_error(context, "dev_activity", %{text: "something"})

      assert error_msg =~ "The provided selector"
      assert error_msg =~ "is not supported"
    end
  end

  describe "aggregated_timeseries_data with unsupported selector" do
    @tag capture_log: true
    test "returns proper error for clickhouse metric with organization selector", context do
      error_msg =
        get_aggregated_error(context, "daily_active_addresses", %{organization: "santiment"})

      assert error_msg =~ "The provided selector"
      assert error_msg =~ "is not supported"
    end
  end

  describe "timeseries_data_per_slug with unsupported selector" do
    @tag capture_log: true
    test "returns proper error for clickhouse metric with organization selector", context do
      error_msg =
        get_timeseries_per_slug_error(context, "daily_active_addresses", %{
          organization: "santiment"
        })

      assert error_msg =~ "The provided selector"
      assert error_msg =~ "is not supported"
    end
  end

  # Private helpers

  defp get_timeseries_error(context, metric, selector) do
    %{conn: conn, from: from, to: to, interval: interval} = context

    query = """
    {
      getMetric(metric: "#{metric}"){
        timeseriesData(
          selector: #{map_to_input_object_str(selector)}
          from: "#{from}"
          to: "#{to}"
          interval: "#{interval}"){
            datetime
            value
          }
      }
    }
    """

    result =
      conn
      |> post("/graphql", query_skeleton(query, "getMetric"))
      |> json_response(200)

    result
    |> get_in(["errors", Access.at(0), "message"])
  end

  defp get_aggregated_error(context, metric, selector) do
    %{conn: conn, from: from, to: to} = context

    query = """
    {
      getMetric(metric: "#{metric}"){
        aggregatedTimeseriesData(
          selector: #{map_to_input_object_str(selector)}
          from: "#{from}"
          to: "#{to}")
      }
    }
    """

    result =
      conn
      |> post("/graphql", query_skeleton(query, "getMetric"))
      |> json_response(200)

    result
    |> get_in(["errors", Access.at(0), "message"])
  end

  defp get_timeseries_per_slug_error(context, metric, selector) do
    %{conn: conn, from: from, to: to, interval: interval} = context

    query = """
    {
      getMetric(metric: "#{metric}"){
        timeseriesDataPerSlug(
          selector: #{map_to_input_object_str(selector)}
          from: "#{from}"
          to: "#{to}"
          interval: "#{interval}"){
            datetime
            data {
              slug
              value
            }
          }
      }
    }
    """

    result =
      conn
      |> post("/graphql", query_skeleton(query, "getMetric"))
      |> json_response(200)

    result
    |> get_in(["errors", Access.at(0), "message"])
  end
end
