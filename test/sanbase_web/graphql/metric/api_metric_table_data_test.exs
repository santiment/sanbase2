defmodule SanbaseWeb.Graphql.ApiMetricTableDataTest do
  use SanbaseWeb.ConnCase, async: false

  import Mock, only: [assert_called: 1]
  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers
  import ExUnit.CaptureLog

  alias Sanbase.Metric

  setup do
    %{user: user} = insert(:subscription_pro_sanbase, user: insert(:user))
    project1 = insert(:random_project)
    project2 = insert(:random_project)
    conn = setup_jwt_auth(build_conn(), user)

    [
      conn: conn,
      slugs: [project1.slug, project2.slug],
      from: ~U[2019-01-01 00:00:00Z],
      to: ~U[2019-01-03 00:00:00Z]
    ]
  end

  test "returns data for an available metric", context do
    %{conn: conn, slugs: slugs, from: from, to: to} = context
    list_of_slugs = Enum.map(slugs, fn slug -> "#{slug}" end)

    metric =
      Metric.available_table_metrics()
      |> Enum.random()

    Sanbase.Mock.prepare_mock2(
      &Sanbase.Clickhouse.MetricAdapter.table_data/5,
      success_result(list_of_slugs)
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        get_table_metric(conn, metric, slugs, from, to)
        |> get_in(["data", "getMetric", "tableData"])

      assert result == %{
               "columns" => list_of_slugs,
               "rows" => ["mercadobitcoin", "banx", "binance"],
               "values" => [[2.0, 3.0], [1.0, 2.0], [1.0, 3.0]]
             }
    end)
  end

  test "returns data for all available metrics", context do
    %{conn: conn, slugs: slugs, from: from, to: to} = context
    list_of_slugs = Enum.map(slugs, fn slug -> "#{slug}" end)

    metrics = Metric.available_table_metrics() |> Enum.shuffle() |> Enum.take(100)

    Sanbase.Mock.prepare_mock2(
      &Sanbase.Clickhouse.MetricAdapter.table_data/5,
      success_result(list_of_slugs)
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        for metric <- metrics do
          get_table_metric(conn, metric, slugs, from, to)
          |> get_in(["data", "getMetric", "tableData"])
        end

      assert Enum.all?(
               result,
               &match?(%{"columns" => _, "rows" => _, "values" => _}, &1)
             )
    end)
  end

  test "market segments selector", context do
    %{conn: conn, from: from, to: to} = context

    market_segment = insert(:market_segment, name: "Stablecoin")
    p1 = insert(:random_project, market_segments: [market_segment])
    p2 = insert(:random_project, market_segments: [market_segment])

    list_of_slugs = [p1.slug, p2.slug]

    Sanbase.Mock.prepare_mock2(
      &Sanbase.Clickhouse.MetricAdapter.table_data/5,
      success_result(list_of_slugs)
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        get_table_metric_ms(
          conn,
          "labelled_exchange_balance_sum",
          market_segment.name,
          [],
          from,
          to
        )
        |> get_in(["data", "getMetric", "tableData"])

      assert result == %{
               "columns" => list_of_slugs,
               "rows" => ["mercadobitcoin", "banx", "binance"],
               "values" => [[2.0, 3.0], [1.0, 2.0], [1.0, 3.0]]
             }

      assert_called(
        Sanbase.Clickhouse.MetricAdapter.table_data(
          "labelled_exchange_balance_sum",
          %{slug: [:_, :_]},
          from,
          to,
          []
        )
      )
    end)
  end

  test "market segments selector with ignored slugs", context do
    %{conn: conn, from: from, to: to} = context

    market_segment = insert(:market_segment, name: "Stablecoin")
    p1 = insert(:random_project, market_segments: [market_segment])
    p2 = insert(:random_project, market_segments: [market_segment])
    p3 = insert(:random_project, market_segments: [market_segment])

    list_of_slugs = [p1.slug, p2.slug]

    Sanbase.Mock.prepare_mock2(
      &Sanbase.Clickhouse.MetricAdapter.table_data/5,
      success_result(list_of_slugs)
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        get_table_metric_ms(
          conn,
          "labelled_exchange_balance_sum",
          market_segment.name,
          [p3.slug],
          from,
          to
        )
        |> get_in(["data", "getMetric", "tableData"])

      assert result == %{
               "columns" => list_of_slugs,
               "rows" => ["mercadobitcoin", "banx", "binance"],
               "values" => [[2.0, 3.0], [1.0, 2.0], [1.0, 3.0]]
             }

      assert_called(
        Sanbase.Clickhouse.MetricAdapter.table_data(
          "labelled_exchange_balance_sum",
          %{slug: [:_, :_]},
          from,
          to,
          []
        )
      )
    end)
  end

  test "returns error for unavailable metrics", context do
    %{conn: conn, slugs: slugs, from: from, to: to} = context
    rand_metrics = Enum.map(1..20, fn _ -> rand_str() end)
    rand_metrics = rand_metrics -- Metric.available_table_metrics()

    # Do not mock the `table_data` function because it's the one that rejects
    for metric <- rand_metrics do
      %{
        "errors" => [
          %{"message" => error_message}
        ]
      } = get_table_metric(conn, metric, slugs, from, to)

      assert error_message ==
               "The metric '#{metric}' is not supported, is deprecated or is mistyped."
    end
  end

  test "returns error when slug is not given", context do
    %{conn: conn, from: from, to: to} = context
    [metric | _] = Metric.available_table_metrics()

    assert capture_log(fn ->
             # Do not mock the `table_data` function because it's the one that rejects
             %{"errors" => [%{"message" => error_message}]} =
               get_table_metric_without_slug(conn, metric, from, to)

             assert error_message =~
                      "Can't fetch #{metric} for an empty selector {}, Reason: \"The selector must have at least one field provided." <>
                        "The available selector fields for a metric are listed in the metadata's availableSelectors field.\""
           end) =~ "Can't fetch #{metric} for an empty selector"
  end

  # Private functions

  defp success_result(list_of_slugs) do
    {:ok,
     %{
       rows: ["mercadobitcoin", "banx", "binance"],
       columns: list_of_slugs,
       values: [[2.0, 3.0], [1.0, 2.0], [1.0, 3.0]]
     }}
  end

  defp get_table_metric(conn, metric, slugs, from, to) do
    query = get_table_query(metric, slugs, from, to)

    conn
    |> post("/graphql", query_skeleton(query, "getMetric"))
    |> json_response(200)
  end

  defp get_table_metric_ms(conn, metric, market_segment, ignored_slug, from, to) do
    query = get_table_query_ms(metric, market_segment, ignored_slug, from, to)

    conn
    |> post("/graphql", query_skeleton(query, "getMetric"))
    |> json_response(200)
  end

  defp get_table_metric_without_slug(conn, metric, from, to) do
    query = get_table_query_without_slug(metric, from, to)

    conn
    |> post("/graphql", query_skeleton(query, "getMetric"))
    |> json_response(200)
  end

  defp get_table_query(metric, slugs, from, to) do
    list_of_slugs =
      Enum.map(slugs, fn slug -> "\"#{slug}\"" end)
      |> Enum.join(",")

    """
      {
        getMetric(metric: "#{metric}"){
          tableData(
            selector: {slugs: [#{list_of_slugs}]}
            from: "#{from}"
            to: "#{to}")
            {
              rows
              columns
              values
            }
        }
      }
    """
  end

  defp get_table_query_ms(metric, market_segment, ignored_slug, from, to) do
    """
      {
        getMetric(metric: "#{metric}"){
          tableData(
            selector: {market_segments: [\"#{market_segment}\"], ignored_slugs: [\"#{ignored_slug}\"]}
            from: "#{from}"
            to: "#{to}")
            {
              rows
              columns
              values
            }
        }
      }
    """
  end

  defp get_table_query_without_slug(metric, from, to) do
    """
      {
        getMetric(metric: "#{metric}"){
          tableData(
            from: "#{from}"
            to: "#{to}")
            {
              rows
              columns
              values
            }
        }
      }
    """
  end
end
