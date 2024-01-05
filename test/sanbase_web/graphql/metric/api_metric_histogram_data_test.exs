defmodule SanbaseWeb.Graphql.ApiMetricHistogramDataTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers
  import ExUnit.CaptureLog

  alias Sanbase.Metric

  setup do
    %{user: user} = insert(:subscription_pro_sanbase, user: insert(:user))
    # So it will work with uniswap metrics as well
    project = insert(:random_project)
    conn = setup_jwt_auth(build_conn(), user)

    [
      conn: conn,
      slug: project.slug,
      from: ~U[2019-01-01 00:00:00Z],
      to: ~U[2019-01-03 00:00:00Z]
    ]
  end

  test "returns data for an available metric", context do
    %{conn: conn, slug: slug, from: from, to: to} = context

    metric =
      Metric.available_histogram_metrics()
      |> Enum.reject(&String.contains?(&1, "uniswap"))
      |> Enum.random()

    Sanbase.Mock.prepare_mock2(
      &Sanbase.Clickhouse.MetricAdapter.histogram_data/6,
      success_result()
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        get_histogram_metric(conn, metric, slug, from, to, "1d", 3)
        |> get_in(["data", "getMetric", "histogramData"])

      assert result == %{
               "values" => %{
                 "data" => [
                   %{"range" => [2.0, 3.0], "value" => 15.0},
                   %{"range" => [3.0, 4.00], "value" => 22.2}
                 ]
               }
             }
    end)
  end

  test "returns data for all available metrics", context do
    %{conn: conn, slug: slug, from: from, to: to} = context

    metrics =
      Metric.available_histogram_metrics()
      |> Enum.reject(&String.contains?(&1, "uniswap"))
      |> Enum.shuffle()
      |> Enum.take(100)

    Sanbase.Mock.prepare_mock2(
      &Sanbase.Clickhouse.MetricAdapter.histogram_data/6,
      {:ok, [%{range: [2.0, 3.0], value: 15.0}]}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        for metric <- metrics do
          get_histogram_metric(conn, metric, slug, from, to, "1d", 100)
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
    end)
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
      } = get_histogram_metric(conn, metric, slug, from, to, "1d", 100)

      assert error_message ==
               "The metric '#{metric}' is not supported, is deprecated or is mistyped."
    end
  end

  test "returns error when slug is not given", context do
    %{conn: conn, from: from, to: to} = context
    limit = 3
    interval = "1d"
    [metric | _] = Metric.available_histogram_metrics()

    assert capture_log(fn ->
             # Do not mock the `timeseries_data` function because it's the one that rejects
             %{"errors" => [%{"message" => error_message}]} =
               get_histogram_metric_without_slug(conn, metric, from, to, interval, limit)

             assert error_message =~
                      "Can't fetch #{metric} for an empty selector {}, Reason: \"The selector must have at least one field provided." <>
                        "The available selector fields for a metric are listed in the metadata's availableSelectors field.\""
           end) =~ "Can't fetch #{metric} for an empty selector"
  end

  test "all_spent_coins_cost histogram - converts interval to full days and successfully returns",
       context do
    %{conn: conn, slug: slug, to: to} = context
    metric = "all_spent_coins_cost"

    Sanbase.Mock.prepare_mock2(
      &Sanbase.Clickhouse.MetricAdapter.histogram_data/6,
      success_result()
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        get_histogram_metric(conn, metric, slug, nil, to, "47h", 3)
        |> get_in(["data", "getMetric", "histogramData"])

      assert result == %{
               "values" => %{
                 "data" => [
                   %{"range" => [2.0, 3.0], "value" => 15.0},
                   %{"range" => [3.0, 4.00], "value" => 22.2}
                 ]
               }
             }
    end)
  end

  test "histogram metric different except without from datetime - returns proper error",
       context do
    %{conn: conn, slug: slug, to: to} = context
    metric = "spent_coins_cost"

    Sanbase.Mock.prepare_mock2(
      &Sanbase.Clickhouse.MetricAdapter.histogram_data/6,
      success_result()
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      capture_log(fn ->
        result = get_histogram_metric(conn, metric, slug, nil, to, "1d", 3)
        error_msg = hd(result["errors"]) |> Map.get("message")

        assert error_msg =~ "Missing required `from` argument"
      end)
    end)
  end

  # Private functions

  defp success_result() do
    {:ok,
     [
       %{range: [2.0, 3.0], value: 15.0},
       %{range: [3.0, 4.0], value: 22.2}
     ]}
  end

  defp get_histogram_metric(conn, metric, slug, from, to, interval, limit) do
    query = get_histogram_query(metric, slug, from, to, interval, limit)

    conn
    |> post("/graphql", query_skeleton(query, "getMetric"))
    |> json_response(200)
  end

  defp get_histogram_metric_without_slug(conn, metric, from, to, interval, limit) do
    query = get_histogram_query_without_slug(metric, from, to, interval, limit)

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
            #{if from, do: "from: \"#{from}\""}
            to: "#{to}"
            interval: "#{interval}"
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

  defp get_histogram_query_without_slug(metric, from, to, interval, limit) do
    """
      {
        getMetric(metric: "#{metric}"){
          histogramData(
            #{if from, do: "from: \"#{from}\""}
            to: "#{to}"
            interval: "#{interval}"
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
