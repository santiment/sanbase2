defmodule Sanbase.Billing.ApiProductAccessTest do
  use SanbaseWeb.ConnCase

  import Sanbase.Factory
  import Sanbase.TestHelpers
  import SanbaseWeb.Graphql.TestHelpers
  import Mock
  import Sanbase.DateTimeUtils, only: [from_iso8601!: 1]

  alias Sanbase.Auth.Apikey
  alias Sanbase.Clickhouse.Metric

  setup_all_with_mocks([
    {Sanbase.Prices.Store, [], [fetch_prices_with_resolution: fn _, _, _, _ -> price_resp() end]},
    {Sanbase.Clickhouse.MVRV, [], [mvrv_ratio: fn _, _, _, _ -> mvrv_resp() end]},
    {Sanbase.Clickhouse.DailyActiveDeposits, [],
     [active_deposits: fn _, _, _, _ -> daily_active_deposits_resp() end]},
    {Sanbase.Clickhouse.NetworkGrowth, [],
     [network_growth: fn _, _, _, _ -> network_growth_resp() end]},
    {Metric, [:passthrough], [get: fn _, _, _, _, _, _ -> metric_resp() end]}
  ]) do
    :ok
  end

  setup do
    user = insert(:user)
    project = insert(:random_project)

    {:ok, apikey} = Apikey.generate_apikey(user)
    conn = setup_apikey_auth(build_conn(), apikey)

    [user: user, conn: conn, project: project]
  end

  describe "SANApi product, No subscription" do
    test "can access FREE v2 clickhouse metrics for all time", context do
      {from, to} = from_to(1500, 0)
      metric = v2_free_metric()
      query = metric_query(metric, from, to)
      result = execute_query(context.conn, query, "getMetric")
      assert_called(Metric.get(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "cannot access RESTRICTED v2 clickhouse metrics for over 3 months", context do
      {from, to} = from_to(91, 10)
      metric = v2_restricted_metric()
      query = metric_query(metric, from, to)
      result = execute_query(context.conn, query, "getMetric")

      assert_called(Metric.get(metric, :_, :_, :_, :_, :_))
      refute called(Metric.get(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "can access FREE metrics for all time", context do
      {from, to} = from_to(1500, 0)
      query = history_price_query(context.project, from, to)
      result = execute_query(context.conn, query, "historyPrice")

      assert_called(Sanbase.Prices.Store.fetch_prices_with_resolution(:_, from, to, :_))
      assert result != nil
    end

    test "cannot access BASIC metrics for over 3 months", context do
      {from, to} = from_to(91, 10)
      query = network_growth_query(from, to)
      result = execute_query(context.conn, query, "networkGrowth")

      refute called(Sanbase.Clickhouse.NetworkGrowth.network_growth(:_, from, to, :_))
      assert result != nil
    end

    test "cannot access BASIC metrics realtime", context do
      {from, to} = from_to(10, 0)
      query = network_growth_query(from, to)
      result = execute_query(context.conn, query, "networkGrowth")

      refute called(Sanbase.Clickhouse.NetworkGrowth.network_growth(:_, from, to, :_))
      assert result != nil
    end

    test "can access BASIC metrics within 90 days and 1 day interval", context do
      {from, to} = from_to(89, 2)
      query = network_growth_query(from, to)
      result = execute_query(context.conn, query, "networkGrowth")

      assert_called(Sanbase.Clickhouse.NetworkGrowth.network_growth(:_, from, to, :_))
      assert result != nil
    end

    test "cannot access PRO metrics for over 3 months", context do
      {from, to} = from_to(91, 10)
      query = daily_active_deposits_query(from, to)
      result = execute_query(context.conn, query, "dailyActiveDeposits")

      refute called(Sanbase.Clickhouse.DailyActiveDeposits.active_deposits(:_, from, to, :_))

      assert result != nil
    end

    test "cannot access PRO metrics realtime", context do
      {from, to} = from_to(10, 0)
      query = daily_active_deposits_query(from, to)
      result = execute_query(context.conn, query, "dailyActiveDeposits")

      refute called(Sanbase.Clickhouse.DailyActiveDeposits.active_deposits(:_, from, to, :_))

      assert result != nil
    end

    test "can access PRO within 90 days and 1 day interval", context do
      {from, to} = from_to(89, 2)
      query = daily_active_deposits_query(from, to)
      result = execute_query(context.conn, query, "dailyActiveDeposits")

      assert_called(Sanbase.Clickhouse.DailyActiveDeposits.active_deposits(:_, from, to, :_))
      assert result != nil
    end
  end

  describe "SANApi product, user with BASIC plan" do
    setup context do
      insert(:subscription_essential, user: context.user)
      :ok
    end

    test "can access FREE v2 clickhouse metrics for all time", context do
      {from, to} = from_to(1500, 0)
      metric = v2_free_metric()
      query = metric_query(metric, from, to)
      result = execute_query(context.conn, query, "getMetric")
      assert called(Metric.get(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "can access RESTRICTED v2 clickhouse metrics for less than 180 days", context do
      {from, to} = from_to(179, 170)
      metric = v2_restricted_metric()
      query = metric_query(metric, from, to)
      result = execute_query(context.conn, query, "getMetric")

      assert called(Metric.get(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "cannot access RESTRICTED v2 clickhouse metrics for over 180 days", context do
      {from, to} = from_to(181, 179)
      metric = v2_restricted_metric()
      query = metric_query(metric, from, to)
      result = execute_query(context.conn, query, "getMetric")

      assert_called(Metric.get(metric, :_, :_, :_, :_, :_))
      refute called(Metric.get(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "can access RESTRICTED v2 clickhouse metrics realtime", context do
      {from, to} = from_to(10, 0)
      metric = v2_restricted_metric()
      query = metric_query(metric, from, to)
      result = execute_query(context.conn, query, "getMetric")

      assert called(Metric.get(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "can access FREE metrics for all time", context do
      {from, to} = from_to(1500, 0)
      query = history_price_query(context.project, from, to)
      result = execute_query(context.conn, query, "historyPrice")

      assert_called(Sanbase.Prices.Store.fetch_prices_with_resolution(:_, from, to, :_))
      assert result != nil
    end

    test "cannot access BASIC metrics for more than 180 days", context do
      {from, to} = from_to(181, 3)
      query = network_growth_query(from, to)
      result = execute_query(context.conn, query, "networkGrowth")

      refute called(Sanbase.Clickhouse.NetworkGrowth.network_growth(:_, from, to, :_))
      assert result != nil
    end

    test "can access BASIC metrics for less than 180 days", context do
      {from, to} = from_to(179, 3)
      query = network_growth_query(from, to)
      result = execute_query(context.conn, query, "networkGrowth")

      assert_called(Sanbase.Clickhouse.NetworkGrowth.network_growth(:_, from, to, :_))
      assert result != nil
    end

    test "can access BASIC metrics realtime", context do
      {from, to} = from_to(10, 0)
      query = network_growth_query(from, to)
      result = execute_query(context.conn, query, "networkGrowth")

      assert_called(Sanbase.Clickhouse.NetworkGrowth.network_growth(:_, from, to, :_))
      assert result != nil
    end

    test "can access PRO metrics", context do
      {from, to} = from_to(91, 0)
      query = daily_active_deposits_query(from, to)

      result = execute_query(context.conn, query, "dailyActiveDeposits")
      assert result != nil
    end
  end

  describe "SANApi product, user with PRO plan" do
    setup context do
      insert(:subscription_pro, user: context.user)
      :ok
    end

    test "can access FREE v2 clickhouse metrics for all time", context do
      {from, to} = from_to(1500, 0)
      metric = v2_free_metric()
      query = metric_query(metric, from, to)
      result = execute_query(context.conn, query, "getMetric")
      assert called(Metric.get(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "can access RESTRICTED v2 clickhouse metrics for less than 18 months", context do
      {from, to} = from_to(18 * 30 - 1, 18 * 30 - 2)
      metric = v2_restricted_metric()
      query = metric_query(metric, from, to)
      result = execute_query(context.conn, query, "getMetric")

      assert called(Metric.get(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "cannot access RESTRICTED v2 clickhouse metrics for over 18 months", context do
      {from, to} = from_to(18 * 30 + 1, 18 * 30 - 1)
      metric = v2_restricted_metric()
      query = metric_query(metric, from, to)
      result = execute_query(context.conn, query, "getMetric")

      assert_called(Metric.get(metric, :_, :_, :_, :_, :_))
      refute called(Metric.get(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "can access RESTRICTED v2 clickhouse metrics realtime", context do
      {from, to} = from_to(10, 0)
      metric = v2_restricted_metric()
      query = metric_query(metric, from, to)
      result = execute_query(context.conn, query, "getMetric")

      assert called(Metric.get(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "can access FREE metrics for all time", context do
      {from, to} = from_to(1500, 0)
      query = history_price_query(context.project, from, to)
      result = execute_query(context.conn, query, "historyPrice")

      assert_called(Sanbase.Prices.Store.fetch_prices_with_resolution(:_, from, to, :_))
      assert result != nil
    end

    test "cannot access BASIC metrics for more than 18 months", context do
      {from, to} = from_to(18 * 30 + 1, 0)
      query = network_growth_query(from, to)
      result = execute_query(context.conn, query, "networkGrowth")

      refute called(Sanbase.Clickhouse.NetworkGrowth.network_growth(:_, from, to, :_))
      assert result != nil
    end

    test "can access BASIC metrics for less than 18 months", context do
      {from, to} = from_to(18 * 30 - 1, 0)
      query = network_growth_query(from, to)
      result = execute_query(context.conn, query, "networkGrowth")

      assert_called(Sanbase.Clickhouse.NetworkGrowth.network_growth(:_, from, to, :_))
      assert result != nil
    end

    test "cannot access PRO metrics for more than 18 months", context do
      {from, to} = from_to(18 * 30 + 1, 0)
      query = daily_active_deposits_query(from, to)
      result = execute_query(context.conn, query, "dailyActiveDeposits")

      refute called(Sanbase.Clickhouse.DailyActiveDeposits.active_deposits(:_, from, to, :_))
      assert result != nil
    end

    test "can access PRO metrics for less than 18 months", context do
      {from, to} = from_to(18 * 30 - 1, 0)
      query = daily_active_deposits_query(from, to)
      result = execute_query(context.conn, query, "dailyActiveDeposits")

      assert_called(Sanbase.Clickhouse.DailyActiveDeposits.active_deposits(:_, from, to, :_))
      assert result != nil
    end
  end

  describe "SANApi product, user with PREMIUM plan" do
    setup context do
      insert(:subscription_premium, user: context.user)
      :ok
    end

    test "can access FREE v2 clickhouse metrics for all time", context do
      {from, to} = from_to(1500, 0)
      metric = v2_free_metric()
      query = metric_query(metric, from, to)
      result = execute_query(context.conn, query, "getMetric")
      assert_called(Metric.get(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "can access RESTRICTED v2 clickhouse metrics for all time", context do
      {from, to} = from_to(1500, 0)
      metric = v2_restricted_metric()
      query = metric_query(metric, from, to)
      result = execute_query(context.conn, query, "getMetric")
      assert_called(Metric.get(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "can access FREE metrics for all time", context do
      {from, to} = from_to(1500, 0)
      query = history_price_query(context.project, from, to)
      result = execute_query(context.conn, query, "historyPrice")

      assert_called(Sanbase.Prices.Store.fetch_prices_with_resolution(:_, from, to, :_))
      assert result != nil
    end

    test "can access BASIC metrics for all time", context do
      {from, to} = from_to(1500, 0)
      query = network_growth_query(from, to)
      result = execute_query(context.conn, query, "networkGrowth")

      assert_called(Sanbase.Clickhouse.NetworkGrowth.network_growth(:_, from, to, :_))
      assert result != nil
    end

    test "can access PRO metrics for all time", context do
      {from, to} = from_to(1500, 0)
      query = daily_active_deposits_query(from, to)
      result = execute_query(context.conn, query, "dailyActiveDeposits")

      assert_called(Sanbase.Clickhouse.DailyActiveDeposits.active_deposits(:_, from, to, :_))
      assert result != nil
    end
  end

  # Private functions

  defp v2_free_metric(), do: Metric.free_metrics() |> Enum.random()
  defp v2_restricted_metric(), do: Metric.restricted_metrics() |> Enum.random()

  defp from_to(from_days_shift, to_days_shift) do
    from = Timex.shift(Timex.now(), days: -from_days_shift)
    to = Timex.shift(Timex.now(), days: -to_days_shift)
    {from, to}
  end

  defp metric_query(metric, from, to) do
    """
      {
        getMetric(metric: "#{metric}") {
          timeseriesData(slug: "ethereum", from: "#{from}", to: "#{to}", interval: "30d"){
            datetime
            value
          }
        }
      }
    """
  end

  defp daily_active_deposits_query(from, to) do
    """
      {
        dailyActiveDeposits(slug: "ethereum", from: "#{from}", to: "#{to}", interval: "1d"){
          datetime
          activeDeposits
        }
      }
    """
  end

  defp network_growth_query(from, to) do
    """
      {
        networkGrowth(slug: "ethereum", from: "#{from}", to: "#{to}", interval: "1d"){
          datetime
          newAddresses
        }
      }
    """
  end

  defp history_price_query(%{slug: slug}, from, to) do
    """
      {
        historyPrice(slug: "#{slug}", from: "#{from}", to: "#{to}", interval: "30d"){
          datetime
          priceUsd
        }
      }
    """
  end

  defp metric_resp() do
    {:ok,
     [
       %{value: 10.0, datetime: from_iso8601!("2019-01-01T00:00:00Z")},
       %{value: 20.0, datetime: from_iso8601!("2019-01-02T00:00:00Z")}
     ]}
  end

  defp mvrv_resp() do
    {:ok,
     [
       %{ratio: 0.1, datetime: from_iso8601!("2019-01-01T00:00:00Z")},
       %{ratio: 0.2, datetime: from_iso8601!("2019-01-02T00:00:00Z")}
     ]}
  end

  defp daily_active_deposits_resp() do
    {:ok,
     [
       %{active_deposits: 0.1, datetime: from_iso8601!("2019-01-01T00:00:00Z")},
       %{active_deposits: 0.2, datetime: from_iso8601!("2019-01-02T00:00:00Z")}
     ]}
  end

  defp price_resp() do
    {:ok,
     [
       [from_iso8601!("2019-01-01T00:00:00Z"), 10, 0.1, 10_000, 500],
       [from_iso8601!("2019-01-01T00:00:00Z"), 20, 0.2, 20_000, 1500]
     ]}
  end

  defp network_growth_resp() do
    {:ok,
     [
       %{new_addresses: 10, datetime: from_iso8601!("2019-01-01T00:00:00Z")},
       %{new_addresses: 20, datetime: from_iso8601!("2019-01-02T00:00:00Z")}
     ]}
  end
end
