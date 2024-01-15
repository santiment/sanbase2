defmodule Sanbase.Graphql.ApiMetricSocialMetricsTimeframeRestrictionTest do
  use SanbaseWeb.ConnCase, async: false

  import Mock
  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.TestHelpers

  alias Sanbase.Metric

  setup_all_with_mocks([
    {Sanbase.Metric, [:passthrough], [timeseries_data: fn _, _, _, _, _, _ -> metric_resp() end]}
  ]) do
    []
  end

  setup do
    user = insert(:user)
    project = insert(:random_erc20_project)

    conn = setup_jwt_auth(build_conn(), user)

    # These metrics have restricted historical data and free realtime data
    metrics = [
      "social_volume_bitcointalk",
      "social_volume_reddit",
      "social_volume_telegram",
      "social_volume_total",
      "social_volume_twitter"
    ]

    [user: user, conn: conn, project: project, metrics: metrics]
  end

  describe "SANBase product, No subscription" do
    test "cannot access realtime data for social metrics", context do
      {from, to} = from_to(2, 0)
      slug = context.project.slug
      metric = Enum.random(context.metrics)
      interval = "5m"
      query = metric_query(metric, slug, from, to, interval)

      result = execute_query_with_error(context.conn, query, "getMetric")

      refute called(Metric.timeseries_data(metric, :_, from, to, :_, :_))

      assert result =~
               "Both `from` and `to` parameters are outside the allowed interval you can query"
    end

    test "cannot access historical data for social metrics", context do
      {from, to} = from_to(5 * 365, 2 * 365)
      slug = context.project.slug
      metric = Enum.random(context.metrics)
      interval = "1d"
      query = metric_query(metric, slug, from, to, interval)
      result = execute_query_with_error(context.conn, query, "getMetric")

      refute called(Metric.timeseries_data(metric, :_, from, to, :_, :_))

      assert result =~
               "Both `from` and `to` parameters are outside the allowed interval you can query"
    end
  end

  describe "SANBase product, user with PRO plan" do
    setup context do
      insert(:subscription_pro_sanbase, user: context.user)
      :ok
    end

    test "can access realtime data for social metrics", context do
      {from, to} = from_to(2, 0)
      slug = context.project.slug
      metric = Enum.random(context.metrics)
      interval = "5m"
      query = metric_query(metric, slug, from, to, interval)
      result = execute_query(context.conn, query, "getMetric")

      assert_called(Metric.timeseries_data(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "can access historical data for social metrics", context do
      {from, to} = from_to(5 * 365, 2 * 365)
      slug = context.project.slug
      metric = Enum.random(context.metrics)
      interval = "1d"
      query = metric_query(metric, slug, from, to, interval)
      result = execute_query(context.conn, query, "getMetric")

      assert_called(Metric.timeseries_data(metric, :_, from, to, :_, :_))
      assert result != nil
    end
  end

  # Private functions

  defp metric_query(metric, slug, from, to, interval) do
    """
      {
        getMetric(metric: "#{metric}") {
          timeseriesData(
            slug: "#{slug}"
            from: "#{from}"
            to: "#{to}"
            interval: "#{interval}"){
              datetime
              value
          }
        }
      }
    """
  end

  defp metric_resp() do
    {:ok,
     [
       %{value: 10.0, datetime: ~U[2019-01-01 00:00:00Z]},
       %{value: 20.0, datetime: ~U[2019-01-02 00:00:00Z]}
     ]}
  end
end
