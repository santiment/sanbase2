defmodule SanbaseWeb.Graphql.ApiMetricEmptyIntervalTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    %{user: user} =
      insert(:subscription_pro_sanbase, user: insert(:user, metric_access_level: "alpha"))

    project = insert(:random_project)
    conn = setup_jwt_auth(build_conn(), user)

    %{conn: conn, slug: project.slug}
  end

  @tag capture_log: true
  test "timeseriesData with an empty interval is auto-calibrated", context do
    data = [
      %{value: 100.0, datetime: ~U[2019-01-01 00:00:00Z]},
      %{value: 200.0, datetime: ~U[2019-01-02 00:00:00Z]}
    ]

    query = empty_interval_query(context.slug)

    Sanbase.Mock.prepare_mock2(
      &Sanbase.Clickhouse.MetricAdapter.first_datetime/3,
      {:ok, ~U[2015-01-01 00:00:00Z]}
    )
    |> Sanbase.Mock.prepare_mock2(
      &Sanbase.Clickhouse.MetricAdapter.timeseries_data/6,
      {:ok, data}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      result = execute_query(context.conn, query)

      refute Map.has_key?(result, "errors"), "Got errors: #{inspect(result["errors"])}"

      assert get_in(result, ["data", "getMetric", "timeseriesData"]) == [
               %{"datetime" => "2019-01-01T00:00:00Z", "value" => 100.0},
               %{"datetime" => "2019-01-02T00:00:00Z", "value" => 200.0}
             ]
    end)
  end

  @tag capture_log: true
  test "a first_datetime error during auto-calibration is returned, not raised", context do
    Sanbase.Mock.prepare_mock2(
      &Sanbase.Clickhouse.MetricAdapter.first_datetime/3,
      {:error, "Cannot execute database query."}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      result = execute_query(context.conn, empty_interval_query(context.slug))

      assert get_in(result, ["data", "getMetric", "timeseriesData"]) == nil
      assert [%{"message" => message}] = result["errors"]
      assert message =~ "Cannot execute database query."
      refute message =~ "no match of right hand side value"
    end)
  end

  defp empty_interval_query(slug) do
    """
    {
      getMetric(metric: "daily_active_addresses"){
        timeseriesData(
          slug: "#{slug}"
          from: "2019-01-01T00:00:00Z"
          to: "2019-01-03T00:00:00Z"
          interval: ""){
            datetime
            value
        }
      }
    }
    """
  end
end
