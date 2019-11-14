defmodule SanbaseWeb.Graphql.Clickhouse.ApiMetricTimeseriesDataTest do
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
      from: from_iso8601!("2019-01-01T00:00:00Z"),
      to: from_iso8601!("2019-01-02T00:00:00Z"),
      interval: "1d"
    ]
  end

  test "returns data for an available metric", context do
    %{conn: conn, slug: slug, from: from, to: to, interval: interval} = context
    aggregation = :avg
    [metric | _] = Metric.available_metrics()

    with_mock Metric, [],
      timeseries_data: fn _, _, _, _, _, _ ->
        {:ok,
         [
           %{value: 100.0, datetime: from_iso8601!("2019-01-01T00:00:00Z")},
           %{value: 200.0, datetime: from_iso8601!("2019-01-02T00:00:00Z")}
         ]}
      end do
      result =
        get_metric(conn, metric, slug, from, to, interval, aggregation)
        |> extract_timeseries_data()

      assert result == [
               %{
                 "value" => 100.0,
                 "datetime" => "2019-01-01T00:00:00Z"
               },
               %{
                 "value" => 200.0,
                 "datetime" => "2019-01-02T00:00:00Z"
               }
             ]

      assert_called(Metric.timeseries_data(metric, slug, from, to, interval, aggregation))
    end
  end

  test "returns data for all available metrics", context do
    %{conn: conn, slug: slug, from: from, to: to, interval: interval} = context
    aggregation = :avg
    metrics = Metric.available_metrics()

    with_mock Metric, [],
      timeseries_data: fn _, _, _, _, _, _ ->
        {:ok,
         [
           %{value: 100.0, datetime: from_iso8601!("2019-01-01T00:00:00Z")},
           %{value: 200.0, datetime: from_iso8601!("2019-01-02T00:00:00Z")}
         ]}
      end do
      result =
        for metric <- metrics do
          get_metric(conn, metric, slug, from, to, interval, aggregation)
          |> extract_timeseries_data()
        end

      # Assert that all results are lists where we have a map with values
      assert Enum.all?(result, &match?([%{"datetime" => _, "value" => _} | _], &1))
    end
  end

  test "returns data for all available aggregations", context do
    %{conn: conn, slug: slug, from: from, to: to, interval: interval} = context
    aggregations = Metric.available_aggregations()
    # nil means aggregation is not passed, we should not explicitly pass it
    aggregations = aggregations -- [nil]
    [metric | _] = Metric.available_metrics()

    with_mock Metric, [],
      timeseries_data: fn _, _, _, _, _, _ ->
        {:ok,
         [
           %{value: 100.0, datetime: from_iso8601!("2019-01-01T00:00:00Z")},
           %{value: 200.0, datetime: from_iso8601!("2019-01-02T00:00:00Z")}
         ]}
      end do
      result =
        for aggregation <- aggregations do
          get_metric(conn, metric, slug, from, to, interval, aggregation)
          |> extract_timeseries_data()
        end

      # Assert that all results are lists where we have a map with values
      assert Enum.all?(result, &match?([%{"datetime" => _, "value" => _} | _], &1))
    end
  end

  test "returns error for unavailable aggregations", context do
    %{conn: conn, slug: slug, from: from, to: to, interval: interval} = context
    aggregations = Metric.available_aggregations()
    rand_aggregations = Enum.map(1..10, fn _ -> rand_str() |> String.to_atom() end)
    rand_aggregations = rand_aggregations -- aggregations
    [metric | _] = Metric.available_metrics()

    # Do not mock the `get` function. It will reject the query if the execution
    # reaches it. Currently the execution is halted even earlier because the
    # aggregation is an enum with available values
    result =
      for aggregation <- rand_aggregations do
        get_metric(conn, metric, slug, from, to, interval, aggregation)
      end

    # Assert that all results are lists where we have a map with values
    assert Enum.all?(result, &match?(%{"errors" => _}, &1))
  end

  test "logs warnings for unavailable metrics", context do
    %{conn: conn, slug: slug, from: from, to: to, interval: interval} = context
    aggregation = :avg
    rand_metrics = Enum.map(1..100, fn _ -> rand_str() end)
    rand_metrics = rand_metrics -- Metric.available_metrics()

    # Do not mock the `get` function because it's the one that rejects
    for metric <- rand_metrics do
      assert capture_log(fn ->
               get_metric(conn, metric, slug, from, to, interval, aggregation)
             end) =~ "Can't fetch #{metric} for project with slug: #{slug}"
    end
  end

  @moduletag capture_log: true
  test "returns error for unavailable metrics", context do
    %{conn: conn, slug: slug, from: from, to: to, interval: interval} = context
    aggregation = :avg
    rand_metrics = Enum.map(1..100, fn _ -> rand_str() end)
    rand_metrics = rand_metrics -- Metric.available_metrics()

    # Do not mock the `get` function because it's the one that rejects
    result =
      for metric <- rand_metrics do
        get_metric(conn, metric, slug, from, to, interval, aggregation)
      end

    # Assert that all results are lists where we have a map with values
    assert Enum.all?(result, &match?(%{"errors" => _}, &1))
  end

  # Private functions

  defp get_metric(conn, metric, slug, from, to, interval, aggregation) do
    query = get_timeseries_query(metric, slug, from, to, interval, aggregation)

    conn
    |> post("/graphql", query_skeleton(query, "getMetric"))
    |> json_response(200)
  end

  defp extract_timeseries_data(result) do
    %{"data" => %{"getMetric" => %{"timeseriesData" => timeseries_data}}} = result
    timeseries_data
  end

  defp get_timeseries_query(metric, slug, from, to, interval, aggregation) do
    """
      {
        getMetric(metric: "#{metric}"){
          timeseriesData(
            slug: "#{slug}",
            from: "#{from}",
            to: "#{to}",
            interval: "#{interval}",
            aggregation: #{Atom.to_string(aggregation) |> String.upcase()}){
              datetime
              value
            }
        }
      }
    """
  end
end
