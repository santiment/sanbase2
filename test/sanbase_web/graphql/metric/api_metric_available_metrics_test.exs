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

      assert Enum.sort(result) == Enum.sort(metrics)
    end)
  end

  test "available metrics with selector contract address", context do
    available_metrics = Sanbase.Metric.available_metrics()

    metrics =
      available_metrics |> Enum.shuffle() |> Enum.take(Enum.random(1..length(available_metrics)))

    Sanbase.Mock.prepare_mock2(&Sanbase.Metric.available_metrics_for_selector/1, {:ok, metrics})
    |> Sanbase.Mock.run_with_mocks(fn ->
      result = get_available_metrics_for_selector(context.conn, %{contract_address: "0x1"})

      assert Enum.sort(result) == Enum.sort(metrics)
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

  def get_available_metrics2(conn) do
    query = """
    {
      getAvailableMetrics
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

  describe "metrics visibility based on user access level" do
    setup do
      # Set up test metrics with different status levels
      {:ok, alpha_metric} = Sanbase.Metric.Registry.by_name("price_usd_5m", "timeseries")
      {:ok, beta_metric} = Sanbase.Metric.Registry.by_name("daily_active_addresses", "timeseries")

      # Update metrics status
      {:ok, _} = Sanbase.Metric.Registry.update(alpha_metric, %{status: "alpha"})
      {:ok, _} = Sanbase.Metric.Registry.update(beta_metric, %{status: "beta"})

      # Refresh registry to ensure changes are visible
      Sanbase.Metric.Registry.refresh_stored_terms()

      :ok
    end

    test "alpha users can see all available metrics" do
      user = insert(:user, metric_access_level: "alpha")
      insert(:subscription_pro_sanbase, user: user)
      conn = setup_jwt_auth(build_conn(), user)

      metrics = get_available_metrics2(conn)

      # Alpha users should see all metrics including alpha and beta ones
      assert "price_usd_5m" in metrics
      assert "daily_active_addresses" in metrics
    end

    test "beta users can see released and beta metrics" do
      user = insert(:user, metric_access_level: "beta")
      insert(:subscription_pro_sanbase, user: user)
      conn = setup_jwt_auth(build_conn(), user)

      metrics = get_available_metrics2(conn)

      # Beta users should not see alpha metrics
      refute "price_usd_5m" in metrics
      # But should see beta and released metrics
      assert "daily_active_addresses" in metrics
      assert "price_usd" in metrics
    end

    test "regular users can see only released metrics" do
      user = insert(:user, metric_access_level: "released")
      insert(:subscription_pro_sanbase, user: user)
      conn = setup_jwt_auth(build_conn(), user)

      metrics = get_available_metrics2(conn)

      # Regular users should only see released metrics
      refute "price_usd_5m" in metrics
      refute "daily_active_addresses" in metrics
      assert "price_usd" in metrics
    end

    test "unauthenticated users can see only released metrics" do
      conn = build_conn()

      metrics = get_available_metrics2(conn)

      # Unauthenticated users should only see released metrics
      refute "price_usd_5m" in metrics
      refute "daily_active_addresses" in metrics
      assert "price_usd" in metrics
    end
  end
end
