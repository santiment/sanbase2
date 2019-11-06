defmodule SanbaseWeb.Graphql.Clickhouse.ApiMetricHistogramDataTest do
  use SanbaseWeb.ConnCase, async: false

  import Mock
  import Sanbase.Factory
  import ExUnit.CaptureLog
  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.DateTimeUtils, only: [from_iso8601!: 1]

  alias Sanbase.Metric

  setup do
    %{user: user} = insert(:subscription_pro_sanbase, user: insert(:user))
    conn = setup_jwt_auth(build_conn(), user)

    [
      conn: conn,
      slug: "ethereum",
      datetime: from_iso8601!("2019-01-01T00:00:00Z")
    ]
  end

  test "returns data for an available metric", context do
    %{conn: conn, slug: slug, datetime: datetime} = context
    [metric | _] = Metric.available_histogram_metrics()

    with_mock Metric, [],
      histogram_data: fn _, _, _ ->
        {:ok,
         %{
           datetime: from_iso8601!("2019-01-01T00:00:00Z"),
           labels: ["l1", "l2", "l3"],
           values: [1, 2, 3]
         }}
      end do
      result =
        get_histogram_metric(conn, metric, slug, datetime)
        |> extract_histogram_data()

      assert result == %{
               "labels" => ["l1", "l2", "l3"],
               "values" => %{"__typename" => "IntegerList", "data" => [1, 2, 3]}
             }

      assert_called(Metric.histogram_data(metric, slug, datetime))
    end
  end

  test "returns data for all available metrics", context do
    %{conn: conn, slug: slug, datetime: datetime} = context
    metrics = Metric.available_histogram_metrics()

    with_mock Metric, [],
      histogram_data: fn _, _, _ ->
        {:ok,
         %{
           datetime: from_iso8601!("2019-01-01T00:00:00Z"),
           labels: ["l1", "l2", "l3"],
           values: [1, 2, 3]
         }}
      end do
      result =
        for metric <- metrics do
          get_histogram_metric(conn, metric, slug, datetime)
          |> extract_histogram_data()
        end

      # Assert that all results are lists where we have a map with values
      assert Enum.all?(
               result,
               &match?(%{"labels" => _, "values" => %{"__typename" => _, "data" => _}}, &1)
             )
    end
  end

  test "logs warnings for unavailable metrics", context do
    %{conn: conn, slug: slug, datetime: datetime} = context
    rand_metrics = Enum.map(1..100, fn _ -> rand_str() end)
    rand_metrics = rand_metrics -- Metric.available_histogram_metrics()

    # Do not mock the `histogram_data` function because it's the one that rejects
    for metric <- rand_metrics do
      assert capture_log(fn ->
               get_histogram_metric(conn, metric, slug, datetime)
             end) =~ "Can't fetch #{metric} for project with slug: #{slug}"
    end
  end

  @moduletag capture_log: true
  test "returns error for unavailable metrics", context do
    %{conn: conn, slug: slug, datetime: datetime} = context
    rand_metrics = Enum.map(1..100, fn _ -> rand_str() end)
    rand_metrics = rand_metrics -- Metric.available_histogram_metrics()

    # Do not mock the `histogram_data` function because it's the one that rejects
    result =
      for metric <- rand_metrics do
        get_histogram_metric(conn, metric, slug, datetime)
      end

    # Assert that all results are lists where we have a map with values
    assert Enum.all?(result, &match?(%{"errors" => _}, &1))
  end

  # Private functions

  defp get_histogram_metric(conn, metric, slug, datetime) do
    query = get_histogram_query(metric, slug, datetime)

    conn
    |> post("/graphql", query_skeleton(query, "getMetric"))
    |> json_response(200)
  end

  defp extract_histogram_data(result) do
    %{"data" => %{"getMetric" => %{"histogramData" => histogram_data}}} = result
    histogram_data
  end

  defp get_histogram_query(metric, slug, datetime) do
    """
      {
        getMetric(metric: "#{metric}"){
          histogramData(
            slug: "#{slug}"
            datetime: "#{datetime}")
            {
              labels
              values {
                __typename
                ... on StringList {
                  data
                }
                ... on FloatList {
                  data
                }
                ... on IntegerList {
                  data
                }
              }
            }
        }
      }
    """
  end
end
