defmodule SanbaseWeb.Graphql.ApiMetricHistogramDataTest do
  use SanbaseWeb.ConnCase, async: false

  import Mock
  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.DateTimeUtils, only: [from_iso8601!: 1]

  alias Sanbase.Metric

  setup do
    %{user: user} = insert(:subscription_pro_sanbase, user: insert(:user))
    conn = setup_jwt_auth(build_conn(), user)

    [
      conn: conn,
      slug: "ethereum",
      from: from_iso8601!("2019-01-01T00:00:00Z"),
      to: from_iso8601!("2019-01-03T00:00:00Z")
    ]
  end

  test "returns data for an available metric", context do
    %{conn: conn, slug: slug, from: from, to: to} = context
    [metric | _] = Metric.available_histogram_metrics()
    interval = "1d"
    limit = 3

    with_mock Metric, [:passthrough],
      histogram_data: fn _, _, _, _, _, _ ->
        {:ok,
         [
           %{
             range: [2.0, 3.0],
             value: 15.0
           },
           %{
             range: [3.0, 4.0],
             value: 22.2
           }
         ]}
      end do
      result =
        get_histogram_metric(conn, metric, slug, from, to, interval, limit)
        |> get_in(["data", "getMetric", "histogramData"])

      assert result == %{
               "values" => %{
                 "data" => [
                   %{"range" => [2.0, 3.0], "value" => 15.0},
                   %{"range" => [3.0, 4.00], "value" => 22.2}
                 ]
               }
             }

      assert_called(Metric.histogram_data(metric, %{slug: slug}, from, to, "1d", 3))
    end
  end

  test "returns data for all available metrics", context do
    %{conn: conn, slug: slug, from: from, to: to} = context
    metrics = Metric.available_histogram_metrics()

    with_mock Metric, [:passthrough],
      histogram_data: fn _, _, _, _, _, _ ->
        {:ok,
         [
           %{
             range: [2.0, 3.0],
             value: 15.0
           }
         ]}
      end do
      result =
        for metric <- metrics do
          get_histogram_metric(conn, metric, slug, from, to)
          |> get_in(["data", "getMetric", "histogramData"])
        end

      # Assert that all results are lists where we have a map with values
      assert Enum.all?(
               result,
               &match?(
                 %{"values" => %{"data" => [%{"range" => [2.0, 3.0], "value" => 15.0}]}},
                 &1
               )
             )
    end
  end

  test "returns error for unavailable metrics", context do
    %{conn: conn, slug: slug, from: from, to: to} = context
    rand_metrics = Enum.map(1..20, fn _ -> rand_str() end)
    rand_metrics = rand_metrics -- Metric.available_histogram_metrics()

    # Do not mock the `histogram_data` function because it's the one that rejects
    for metric <- rand_metrics do
      %{
        "errors" => [
          %{"message" => error_message}
        ]
      } = get_histogram_metric(conn, metric, slug, from, to)

      assert error_message == "The metric '#{metric}' is not supported or is mistyped."
    end
  end

  # Private functions

  defp get_histogram_metric(conn, metric, slug, from, to, interval \\ "1d", limit \\ 100) do
    query = get_histogram_query(metric, slug, from, to, interval, limit)

    conn
    |> post("/graphql", query_skeleton(query, "getMetric"))
    |> json_response(200)
  end

  defp get_histogram_query(metric, slug, from, to, interval, limit) do
    """
      {
        getMetric(metric: "#{metric}"){
          histogramData(
            slug: "#{slug}"
            from: "#{from}",
            to: "#{to}",
            interval: "#{interval}",
            limit: #{limit})
            {
              values {
                ... on DatetimeRangeFloatValueList{
                  data{
                    range
                    value
                  }
                }

                ... on FloatRangeFloatValueList {
                  data {
                    range
                    value
                  }
                }
              }
            }
        }
      }
    """
  end
end
