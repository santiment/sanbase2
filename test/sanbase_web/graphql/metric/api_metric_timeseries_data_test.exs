defmodule SanbaseWeb.Graphql.ApiMetricTimeseriesDataTest do
  use SanbaseWeb.ConnCase, async: false

  import Mock, only: [assert_called: 1]
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
      to: ~U[2019-01-02 00:00:00Z],
      interval: "1d"
    ]
  end

  test "market segments selector", context do
    %{conn: conn, from: from, to: to, interval: interval} = context

    market_segment = insert(:market_segment, name: "Stablecoin")
    insert(:random_project, market_segments: [market_segment])
    insert(:random_project, market_segments: [market_segment])
    insert(:random_project, market_segments: [market_segment])

    Sanbase.Mock.prepare_mock2(
      &Sanbase.Clickhouse.MetricAdapter.timeseries_data/6,
      {:ok,
       [
         %{value: 100.0, datetime: ~U[2019-01-01 00:00:00Z]},
         %{value: 200.0, datetime: ~U[2019-01-02 00:00:00Z]}
       ]}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        get_timeseries_metric(
          conn,
          "holders_distribution_0.1_to_1",
          %{market_segments: [market_segment.name]},
          from,
          to,
          interval,
          :sum
        )
        |> extract_timeseries_data()

      assert result == [
               %{"value" => 100.0, "datetime" => "2019-01-01T00:00:00Z"},
               %{"value" => 200.0, "datetime" => "2019-01-02T00:00:00Z"}
             ]

      assert_called(
        Sanbase.Clickhouse.MetricAdapter.timeseries_data(
          "holders_distribution_0.1_to_1",
          %{slug: [:_, :_, :_]},
          from,
          to,
          interval,
          :_
        )
      )
    end)
  end

  test "market segments selector with ignored slugs", context do
    %{conn: conn, from: from, to: to, interval: interval} = context

    market_segment = insert(:market_segment, name: "Stablecoin")
    _p1 = insert(:random_project, market_segments: [market_segment])
    _p2 = insert(:random_project, market_segments: [market_segment])
    p3 = insert(:random_project, market_segments: [market_segment])

    Sanbase.Mock.prepare_mock2(
      &Sanbase.Clickhouse.MetricAdapter.timeseries_data/6,
      {:ok,
       [
         %{value: 100.0, datetime: ~U[2019-01-01 00:00:00Z]},
         %{value: 200.0, datetime: ~U[2019-01-02 00:00:00Z]}
       ]}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        get_timeseries_metric(
          conn,
          "holders_distribution_0.1_to_1",
          %{market_segments: [market_segment.name], ignored_slugs: [p3.slug]},
          from,
          to,
          interval,
          :sum
        )
        |> extract_timeseries_data()

      assert result == [
               %{"value" => 100.0, "datetime" => "2019-01-01T00:00:00Z"},
               %{"value" => 200.0, "datetime" => "2019-01-02T00:00:00Z"}
             ]

      assert_called(
        Sanbase.Clickhouse.MetricAdapter.timeseries_data(
          "holders_distribution_0.1_to_1",
          %{slug: [:_, :_]},
          from,
          to,
          interval,
          :_
        )
      )
    end)
  end

  test "returns data for labeled metrics", context do
    %{conn: conn, slug: slug, from: from, to: to, interval: interval} = context

    label_metrics =
      Metric.available_timeseries_metrics()
      |> Enum.filter(fn metric ->
        {:ok, %{available_selectors: selectors}} = Metric.metadata(metric)

        :label in selectors and :owner in selectors
      end)

    Sanbase.Mock.prepare_mock2(
      &Sanbase.Metric.timeseries_data/6,
      {:ok, [%{datetime: ~U[2020-01-01 00:00:00Z], value: 1.0}]}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      for metric <- label_metrics do
        result =
          get_timeseries_metric(
            conn,
            metric,
            %{slug: slug, owner: "Binance", label: "centralized_exchange"},
            from,
            to,
            interval,
            :avg
          )
          |> extract_timeseries_data()

        assert result == [
                 %{"value" => 1.0, "datetime" => "2020-01-01T00:00:00Z"}
               ]
      end
    end)
  end

  test "returns data for an available metric", context do
    %{conn: conn, slug: slug, from: from, to: to, interval: interval} = context
    metric = "daily_active_addresses"
    {:ok, %{default_aggregation: aggregation}} = Metric.metadata(metric)

    Sanbase.Mock.prepare_mock2(
      &Sanbase.Clickhouse.MetricAdapter.timeseries_data/6,
      {:ok,
       [
         %{value: 100.0, datetime: ~U[2019-01-01 00:00:00Z]},
         %{value: 200.0, datetime: ~U[2019-01-02 00:00:00Z]}
       ]}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        get_timeseries_metric(
          conn,
          metric,
          %{slug: slug},
          from,
          to,
          interval,
          aggregation
        )
        |> extract_timeseries_data()

      assert result == [
               %{"value" => 100.0, "datetime" => "2019-01-01T00:00:00Z"},
               %{"value" => 200.0, "datetime" => "2019-01-02T00:00:00Z"}
             ]
    end)
  end

  test "returns data for all available metrics", context do
    %{conn: conn, slug: slug, from: from, to: to, interval: interval} = context
    aggregation = :avg

    metrics = Metric.available_timeseries_metrics() |> Enum.shuffle() |> Enum.take(50)

    Sanbase.Mock.prepare_mock2(
      &Metric.timeseries_data/6,
      {:ok,
       [
         %{value: 100.0, datetime: ~U[2019-01-01 00:00:00Z]},
         %{value: 200.0, datetime: ~U[2019-01-02 00:00:00Z]}
       ]}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        for metric <- metrics do
          get_timeseries_metric(
            conn,
            metric,
            %{slug: slug},
            from,
            to,
            interval,
            aggregation
          )
          |> extract_timeseries_data()
        end

      # Assert that all results are lists where we have a map with values
      assert Enum.all?(
               result,
               &match?([%{"datetime" => _, "value" => _} | _], &1)
             )
    end)
  end

  test "returns data for all available aggregations of a metric", context do
    %{conn: conn, slug: slug, from: from, to: to, interval: interval} = context
    # manually choose a metric that supports all different aggregations
    metric = "daily_active_addresses"
    {:ok, %{available_aggregations: aggregations}} = Metric.metadata(metric)

    Sanbase.Mock.prepare_mock2(
      &Sanbase.Clickhouse.MetricAdapter.timeseries_data/6,
      {:ok,
       [
         %{value: 100.0, datetime: ~U[2019-01-01 00:00:00Z]},
         %{value: 200.0, datetime: ~U[2019-01-02 00:00:00Z]}
       ]}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        for aggregation <- aggregations do
          get_timeseries_metric(
            conn,
            metric,
            %{slug: slug},
            from,
            to,
            interval,
            aggregation
          )
          |> extract_timeseries_data()
        end

      # Assert that all results are lists where we have a map with values
      assert Enum.all?(
               result,
               &match?([%{"datetime" => _, "value" => _} | _], &1)
             )
    end)
  end

  test "returns error for unavailable aggregations", context do
    %{conn: conn, slug: slug, from: from, to: to, interval: interval} = context
    aggregations = Metric.available_aggregations()

    rand_aggregations = Enum.map(1..10, fn _ -> rand_str() |> String.to_atom() end)

    rand_aggregations = rand_aggregations -- aggregations
    [metric | _] = Metric.available_timeseries_metrics()

    # Do not mock the `get` function. It will reject the query if the execution
    # reaches it. Currently the execution is halted even earlier because the
    # aggregation is an enum with available values
    result =
      for aggregation <- rand_aggregations do
        get_timeseries_metric(
          conn,
          metric,
          %{slug: slug},
          from,
          to,
          interval,
          aggregation
        )
      end

    # Assert that all results are lists where we have a map with values
    assert Enum.all?(result, &match?(%{"errors" => _}, &1))
  end

  test "returns error for unavailable metrics", context do
    %{conn: conn, slug: slug, from: from, to: to, interval: interval} = context
    aggregation = :avg
    rand_metrics = Enum.map(1..20, fn _ -> rand_str() end)
    rand_metrics = rand_metrics -- Metric.available_timeseries_metrics()

    # Do not mock the `timeseries_data` function because it's the one that rejects
    for metric <- rand_metrics do
      %{"errors" => [%{"message" => error_message}]} =
        get_timeseries_metric(
          conn,
          metric,
          %{slug: slug},
          from,
          to,
          interval,
          aggregation
        )

      assert error_message ==
               "The metric '#{metric}' is not supported or is mistyped."
    end
  end

  test "returns error when slug is not given", context do
    %{conn: conn, from: from, to: to, interval: interval} = context
    aggregation = :avg
    [metric | _] = Metric.available_timeseries_metrics()

    assert capture_log(fn ->
             # Do not mock the `timeseries_data` function because it's the one that rejects
             %{"errors" => [%{"message" => error_message}]} =
               get_timeseries_metric_without_slug(
                 conn,
                 metric,
                 from,
                 to,
                 interval,
                 aggregation
               )

             assert error_message =~
                      "Can't fetch #{metric} for an empty selector {}, Reason: \"The selector must have at least one field provided." <>
                        "The available selector fields for a metric are listed in the metadata's availableSelectors field.\""
           end) =~ "Can't fetch #{metric} for an empty selector"
  end

  test "complexity for clickhouse metrics is smaller", context do
    slug = "ethereum"
    to = ~U[2020-05-01 00:00:00Z]
    from = ~U[2009-01-01 00:00:00Z]
    interval = "1h"

    ch_metric_error =
      get_timeseries_metric(
        context.conn,
        "mvrv_usd",
        %{slug: slug},
        from,
        to,
        interval,
        :last
      )
      |> get_in(["errors"])
      |> List.first()
      |> get_in(["message"])

    social_metric_error =
      get_timeseries_metric(
        context.conn,
        "social_volume_telegram",
        %{slug: slug},
        from,
        to,
        interval,
        :last
      )
      |> get_in(["errors"])
      |> List.first()
      |> get_in(["message"])

    ch_metric_complexity = error_to_complexity(ch_metric_error)
    social_metric_complexity = error_to_complexity(social_metric_error)

    assert ch_metric_complexity + 1 < social_metric_complexity
  end

  # Private functions

  defp error_to_complexity(error_msg) do
    error_msg
    |> String.split("complexity is ")
    |> List.last()
    |> String.split(" and maximum is")
    |> List.first()
    |> String.to_integer()
  end

  defp get_timeseries_metric(
         conn,
         metric,
         selector,
         from,
         to,
         interval,
         aggregation
       ) do
    query = get_timeseries_query(metric, selector, from, to, interval, aggregation)

    conn
    |> post("/graphql", query_skeleton(query, "getMetric"))
    |> json_response(200)
  end

  defp get_timeseries_metric_without_slug(
         conn,
         metric,
         from,
         to,
         interval,
         aggregation
       ) do
    query = get_timeseries_query_without_slug(metric, from, to, interval, aggregation)

    conn
    |> post("/graphql", query_skeleton(query, "getMetric"))
    |> json_response(200)
  end

  defp extract_timeseries_data(result) do
    %{"data" => %{"getMetric" => %{"timeseriesData" => timeseries_data}}} = result

    timeseries_data
  end

  defp get_timeseries_query(metric, selector, from, to, interval, aggregation) do
    """
      {
        getMetric(metric: "#{metric}"){
          timeseriesData(
            selector: #{map_to_input_object_str(selector)},
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

  defp get_timeseries_query_without_slug(
         metric,
         from,
         to,
         interval,
         aggregation
       ) do
    """
      {
        getMetric(metric: "#{metric}"){
          timeseriesData(
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
