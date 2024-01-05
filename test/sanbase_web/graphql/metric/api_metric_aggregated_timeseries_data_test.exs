defmodule SanbaseWeb.Graphql.ApiMetricAggregatedTimeseriesDataTest do
  use SanbaseWeb.ConnCase, async: false

  import Mock
  import Sanbase.Factory
  import ExUnit.CaptureLog
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Metric

  setup do
    %{user: user} = insert(:subscription_pro_sanbase, user: insert(:user))
    project = insert(:random_project)
    conn = setup_jwt_auth(build_conn(), user)

    [
      conn: conn,
      slug: project.slug,
      from: ~U[2019-01-01 00:00:00Z],
      to: ~U[2019-01-02 00:00:00Z]
    ]
  end

  test "price_usd when the source is cryptocompare", context do
    # Test that when the source is cryptocompare the prices are served from the
    # PricePair module instead of the Price module
    %{conn: conn, slug: slug, from: from, to: to} = context

    Sanbase.Mock.prepare_mock2(
      &Sanbase.PricePair.aggregated_timeseries_data/5,
      {:ok, %{slug => 154.44}}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        get_aggregated_timeseries_metric(
          conn,
          "price_usd",
          %{slug: slug, source: "cryptocompare"},
          from,
          to,
          :last
        )
        |> extract_aggregated_timeseries_data()

      assert result == 154.44

      assert_called(
        Sanbase.PricePair.aggregated_timeseries_data(
          slug,
          "USD",
          from,
          to,
          :_
        )
      )
    end)
  end

  test "returns data for an available metric", context do
    %{conn: conn, slug: slug, from: from, to: to} = context

    Sanbase.Mock.prepare_mock(
      Sanbase.Clickhouse.MetricAdapter,
      :aggregated_timeseries_data,
      fn _, slug, _, _, _ -> {:ok, %{slug => 100}} end
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        get_aggregated_timeseries_metric(
          conn,
          "daily_active_addresses",
          %{slug: slug},
          from,
          to,
          nil
        )
        |> extract_aggregated_timeseries_data()

      assert result == 100
    end)
  end

  test "returns data for all available metrics", context do
    %{conn: conn, slug: slug, from: from, to: to} = context

    metrics =
      Metric.available_timeseries_metrics()
      |> Enum.shuffle()
      |> Enum.take(100)

    Sanbase.Mock.prepare_mock(Metric, :aggregated_timeseries_data, fn _, slug_arg, _, _, _ ->
      {:ok, %{slug_arg => 100}}
    end)
    |> Sanbase.Mock.run_with_mocks(fn ->
      for metric <- metrics do
        result =
          get_aggregated_timeseries_metric(conn, metric, %{slug: slug}, from, to, nil)
          |> extract_aggregated_timeseries_data()

        assert result == 100
      end
    end)
  end

  test "returns data for all available aggregations", context do
    %{conn: conn, slug: slug, from: from, to: to} = context
    # nil means aggregation is not passed, we should not explicitly pass it
    metric = Metric.available_timeseries_metrics() |> Enum.random()
    {:ok, %{available_aggregations: aggregations}} = Metric.metadata(metric)

    Sanbase.Mock.prepare_mock(Metric, :aggregated_timeseries_data, fn _, slug, _, _, _ ->
      {:ok, %{slug => 100}}
    end)
    |> Sanbase.Mock.run_with_mocks(fn ->
      for aggregation <- aggregations do
        result =
          get_aggregated_timeseries_metric(conn, metric, %{slug: slug}, from, to, aggregation)
          |> extract_aggregated_timeseries_data()

        assert result == 100
      end
    end)
  end

  test "returns error for unavailable aggregations", context do
    %{conn: conn, slug: slug, from: from, to: to} = context
    aggregations = Metric.available_aggregations()
    rand_aggregations = Enum.map(1..10, fn _ -> rand_str() |> String.to_atom() end)
    rand_aggregations = rand_aggregations -- aggregations
    [metric | _] = Metric.available_timeseries_metrics()

    # Do not mock the `get` function. It will reject the query if the execution
    # reaches it. Currently the execution is halted even earlier because the
    # aggregation is an enum with available values
    result =
      for aggregation <- rand_aggregations do
        get_aggregated_timeseries_metric(conn, metric, %{slug: slug}, from, to, aggregation)
      end

    # Assert that all results are lists where we have a map with values
    assert Enum.all?(result, &match?(%{"errors" => _}, &1))
  end

  test "returns error for unavailable metrics", context do
    %{conn: conn, slug: slug, from: from, to: to} = context
    aggregation = :avg
    rand_metrics = Enum.map(1..20, fn _ -> rand_str() end)
    rand_metrics = rand_metrics -- Metric.available_timeseries_metrics()

    # Do not mock the `timeseries_data` function because it's the one that rejects
    for metric <- rand_metrics do
      %{"errors" => [%{"message" => error_message}]} =
        get_aggregated_timeseries_metric(conn, metric, %{slug: slug}, from, to, aggregation)

      assert error_message ==
               "The metric '#{metric}' is not supported, is deprecated or is mistyped."
    end
  end

  test "returns error when slug is not given", context do
    %{conn: conn, from: from, to: to} = context
    aggregation = :avg
    [metric | _] = Metric.available_timeseries_metrics()

    assert capture_log(fn ->
             # Do not mock the `timeseries_data` function because it's the one that rejects
             %{"errors" => [%{"message" => error_message}]} =
               get_aggregated_timeseries_metric_without_selector(
                 conn,
                 metric,
                 from,
                 to,
                 aggregation
               )

             assert error_message =~
                      "Can't fetch #{metric} for an empty selector {}, Reason: \"The selector must have at least one field provided." <>
                        "The available selector fields for a metric are listed in the metadata's availableSelectors field.\""
           end) =~ "Can't fetch #{metric} for an empty selector"
  end

  # Private functions

  defp get_aggregated_timeseries_metric(conn, metric, selector, from, to, aggregation) do
    query = get_aggregated_timeseries_query(metric, selector, from, to, aggregation)

    conn
    |> post("/graphql", query_skeleton(query, "getMetric"))
    |> json_response(200)
  end

  defp get_aggregated_timeseries_metric_without_selector(conn, metric, from, to, aggregation) do
    query = get_aggregated_timeseries_query_without_selector(metric, from, to, aggregation)

    conn
    |> post("/graphql", query_skeleton(query, "getMetric"))
    |> json_response(200)
  end

  defp extract_aggregated_timeseries_data(result) do
    result
    |> get_in(["data", "getMetric", "aggregatedTimeseriesData"])
  end

  defp get_aggregated_timeseries_query(metric, selector, from, to, aggregation) do
    # Put so some of the source metrics do not fail. If the source exists do not
    # replace it. In case the source is not needed it won't be used.
    selector = selector |> Map.put_new(:source, "twitter")
    selector = extend_selector_with_required_fields(metric, selector)

    """
      {
        getMetric(metric: "#{metric}"){
          aggregatedTimeseriesData(
            selector: #{map_to_input_object_str(selector)}
            from: "#{from}"
            to: "#{to}"
            #{if aggregation, do: "aggregation: #{Atom.to_string(aggregation) |> String.upcase()}"})
        }
      }
    """
  end

  defp get_aggregated_timeseries_query_without_selector(metric, from, to, aggregation) do
    """
      {
        getMetric(metric: "#{metric}"){
          aggregatedTimeseriesData(
            from: "#{from}"
            to: "#{to}"
            aggregation: #{Atom.to_string(aggregation) |> String.upcase()})
        }
      }
    """
  end
end
