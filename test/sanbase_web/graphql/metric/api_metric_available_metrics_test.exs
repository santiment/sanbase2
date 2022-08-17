defmodule SanbaseWeb.Graphql.AvailableMetricsApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  @moduletag capture_log: true

  setup do
    %{user: user} = insert(:subscription_pro_sanbase, user: insert(:user))
    conn = setup_jwt_auth(build_conn(), user)

    [conn: conn]
  end

  test "get available metrics with regex filter", context do
    metrics = get_available_metrics(context.conn, %{name_regex_filter: "^mean_age_[\\d]+"})
    metrics = Enum.sort(metrics)

    expected =
      Enum.sort([
        "mean_age_180d",
        "mean_age_2y",
        "mean_age_5y",
        "mean_age_365d",
        "mean_age_3y",
        "mean_age_90d"
      ])

    assert metrics == expected
  end

  test "available metrics with selector slug", context do
    available_metrics = Sanbase.Metric.available_metrics()

    metrics =
      available_metrics |> Enum.shuffle() |> Enum.take(Enum.random(1..length(available_metrics)))

    Sanbase.Mock.prepare_mock2(&Sanbase.Metric.available_metrics_for_selector/1, {:ok, metrics})
    |> Sanbase.Mock.run_with_mocks(fn ->
      result = get_available_metrics_for_selector(context.conn, %{slug: "santiment"})

      assert result == metrics
    end)
  end

  test "available metrics with selector contract address", context do
    available_metrics = Sanbase.Metric.available_metrics()

    metrics =
      available_metrics |> Enum.shuffle() |> Enum.take(Enum.random(1..length(available_metrics)))

    Sanbase.Mock.prepare_mock2(&Sanbase.Metric.available_metrics_for_selector/1, {:ok, metrics})
    |> Sanbase.Mock.run_with_mocks(fn ->
      result = get_available_metrics_for_selector(context.conn, %{contract_address: "0x1"})

      assert result == metrics
    end)
  end

  test "available metrics with selector address", context do
    result = get_available_metrics_for_selector(context.conn, %{address: "0x1"})
    assert "nft_collection_max_price_usd" in result
  end

  def get_available_metrics(conn, args) do
    query = """
    {
      getAvailableMetrics(#{map_to_args(args)})
    }
    """

    execute_query(conn, query, "getAvailableMetrics")
  end

  def get_available_metrics_for_selector(conn, selector) do
    query = """
    {
      getAvailableMetricsForSelector(selector:#{map_to_input_object_str(selector)})
    }
    """

    execute_query(conn, query, "getAvailableMetricsForSelector")
  end
end
