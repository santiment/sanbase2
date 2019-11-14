defmodule Sanbase.Billing.ApiProductAccessTest do
  use SanbaseWeb.ConnCase

  import Sanbase.Factory
  import Sanbase.TestHelpers
  import SanbaseWeb.Graphql.TestHelpers
  import Mock
  import Sanbase.DateTimeUtils, only: [from_iso8601!: 1]

  alias Sanbase.Auth.Apikey
  alias Sanbase.Metric

  setup_all_with_mocks([
    {Sanbase.Prices.Store, [], [fetch_prices_with_resolution: fn _, _, _, _ -> price_resp() end]},
    {Sanbase.Clickhouse.DailyActiveDeposits, [],
     [active_deposits: fn _, _, _, _ -> daily_active_deposits_resp() end]},
    {Sanbase.Clickhouse.NetworkGrowth, [],
     [network_growth: fn _, _, _, _ -> network_growth_resp() end]},
    {Metric, [:passthrough], [timeseries_data: fn _, _, _, _, _, _ -> metric_resp() end]}
  ]) do
    :ok
  end

  setup do
    user = insert(:user)
    project = insert(:random_erc20_project)

    {:ok, apikey} = Apikey.generate_apikey(user)
    conn = setup_apikey_auth(build_conn(), apikey)

    [user: user, conn: conn, project: project]
  end

  describe "SANApi product, No subscription" do
    test "can access FREE metrics for all time", context do
      {from, to} = from_to(2500, 0)
      metric = v2_free_metric()
      slug = context.project.slug
      query = metric_query(metric, slug, from, to)
      result = execute_query(context.conn, query, "getMetric")
      assert_called(Metric.timeseries_data(metric, slug, from, to, :_, :_))
      assert result != nil
    end

    test "can access FREE queries for all time", context do
      {from, to} = from_to(2500, 0)
      slug = context.project.slug
      query = history_price_query(slug, from, to)
      result = execute_query(context.conn, query, "historyPrice")
      ticker_slug = context.project.ticker <> "_" <> slug
      assert_called(Sanbase.Prices.Store.fetch_prices_with_resolution(ticker_slug, from, to, :_))
      assert result != nil
    end

    test "cannot access RESTRICTED metrics for over 3 months", context do
      {from, to} = from_to(91, 10)
      metric = v2_restricted_metric()
      slug = context.project.slug
      query = metric_query(metric, slug, from, to)
      result = execute_query(context.conn, query, "getMetric")

      assert_called(Metric.timeseries_data(metric, slug, :_, :_, :_, :_))
      refute called(Metric.timeseries_data(metric, slug, from, to, :_, :_))
      assert result != nil
    end

    test "cannot access RESTRICTED queries for over 3 months", context do
      {from, to} = from_to(91, 10)
      query = network_growth_query(context.project.slug, from, to)
      result = execute_query(context.conn, query, "networkGrowth")
      contract = context.project.main_contract_address

      refute called(Sanbase.Clickhouse.NetworkGrowth.network_growth(contract, from, to, :_))
      assert result != nil
    end

    test "cannot access RESTRICTED queries realtime", context do
      {from, to} = from_to(10, 0)
      query = network_growth_query(context.project.slug, from, to)
      result = execute_query(context.conn, query, "networkGrowth")
      contract = context.project.main_contract_address

      refute called(Sanbase.Clickhouse.NetworkGrowth.network_growth(contract, from, to, :_))
      assert result != nil
    end

    test "cannot access RESTRICTED metrics realtime", context do
      {from, to} = from_to(10, 0)
      query = daily_active_deposits_query(context.project.slug, from, to)
      result = execute_query(context.conn, query, "dailyActiveDeposits")
      contract = context.project.main_contract_address

      refute called(
               Sanbase.Clickhouse.DailyActiveDeposits.active_deposits(contract, from, to, :_)
             )

      assert result != nil
    end

    test "can access RESTRICTED metrics within 90 days and 1 day interval", context do
      {from, to} = from_to(89, 2)
      metric = v2_restricted_metric()
      slug = context.project.slug
      query = metric_query(metric, slug, from, to)
      result = execute_query(context.conn, query, "getMetric")

      assert called(Metric.timeseries_data(metric, slug, from, to, :_, :_))
      assert result != nil
    end

    test "can access RESTRICTED queries within 90 days and 1 day interval", context do
      {from, to} = from_to(89, 2)
      query = daily_active_deposits_query(context.project.slug, from, to)
      result = execute_query(context.conn, query, "dailyActiveDeposits")
      contract = context.project.main_contract_address

      assert_called(
        Sanbase.Clickhouse.DailyActiveDeposits.active_deposits(contract, from, to, :_)
      )

      assert result != nil
    end
  end

  describe "SANApi product, user with BASIC plan" do
    setup context do
      insert(:subscription_essential, user: context.user)
      :ok
    end

    test "can access FREE metrics for all time", context do
      {from, to} = from_to(2500, 0)
      metric = v2_free_metric()
      slug = context.project.slug
      query = metric_query(metric, slug, from, to)
      result = execute_query(context.conn, query, "getMetric")
      assert called(Metric.timeseries_data(metric, slug, from, to, :_, :_))
      assert result != nil
    end

    test "can access FREE queries for all time", context do
      {from, to} = from_to(2500, 0)
      slug = context.project.slug
      query = history_price_query(slug, from, to)
      result = execute_query(context.conn, query, "historyPrice")
      ticker_slug = context.project.ticker <> "_" <> slug
      assert_called(Sanbase.Prices.Store.fetch_prices_with_resolution(ticker_slug, from, to, :_))
      assert result != nil
    end

    test "can access RESTRICTED metrics for less than 3 years", context do
      {from, to} = from_to(3 * 365 - 1, 3 * 365 - 2)
      metric = v2_restricted_metric()
      slug = context.project.slug
      query = metric_query(metric, slug, from, to)
      result = execute_query(context.conn, query, "getMetric")

      assert called(Metric.timeseries_data(metric, slug, from, to, :_, :_))
      assert result != nil
    end

    test "can access RESTRICTED queries for less than 3 years", context do
      {from, to} = from_to(3 * 365 - 1, 3 * 365 - 2)
      query = network_growth_query(context.project.slug, from, to)
      result = execute_query(context.conn, query, "networkGrowth")
      contract = context.project.main_contract_address

      assert_called(Sanbase.Clickhouse.NetworkGrowth.network_growth(contract, from, to, :_))
      assert result != nil
    end

    test "cannot access RESTRICTED queries for more than 3 years", context do
      {from, to} = from_to(3 * 365 + 1, 3 * 365 - 1)
      query = network_growth_query(context.project.slug, from, to)
      result = execute_query(context.conn, query, "networkGrowth")
      contract = context.project.main_contract_address

      refute called(Sanbase.Clickhouse.NetworkGrowth.network_growth(contract, from, to, :_))
      assert result != nil
    end

    test "cannot access RESTRICTED metrics for more than 3 years", context do
      {from, to} = from_to(3 * 365 + 1, 3 * 365 - 1)
      metric = v2_restricted_metric()
      slug = context.project.slug
      query = metric_query(metric, slug, from, to)
      result = execute_query(context.conn, query, "getMetric")

      assert_called(Metric.timeseries_data(metric, slug, :_, :_, :_, :_))
      refute called(Metric.timeseries_data(metric, slug, from, to, :_, :_))
      assert result != nil
    end

    test "cannot access RESTRICTED metrics for more than 3 years - both params outside allowed",
         context do
      {from, to} = from_to(3 * 365 - 10, 3 * 365 - 2)
      metric = v2_restricted_metric()
      slug = context.project.slug
      query = metric_query(metric, slug, from, to)
      result = execute_query_with_error(context.conn, query, "getMetric")

      refute called(Metric.timeseries_data(metric, slug, :_, :_, :_, :_))
      assert result != nil
    end

    test "can access RESTRICTED metrics realtime", context do
      {from, to} = from_to(10, 0)
      metric = v2_restricted_metric()
      slug = context.project.slug
      query = metric_query(metric, slug, from, to)
      result = execute_query(context.conn, query, "getMetric")

      assert called(Metric.timeseries_data(metric, slug, from, to, :_, :_))
      assert result != nil
    end

    test "can access RESTRICTED queries realtime", context do
      {from, to} = from_to(10, 0)
      query = network_growth_query(context.project.slug, from, to)
      result = execute_query(context.conn, query, "networkGrowth")
      contract = context.project.main_contract_address

      assert_called(Sanbase.Clickhouse.NetworkGrowth.network_growth(contract, from, to, :_))
      assert result != nil
    end
  end

  describe "SANApi product, user with PRO plan" do
    setup context do
      insert(:subscription_pro, user: context.user)
      :ok
    end

    test "can access FREE metrics for all time", context do
      {from, to} = from_to(2500, 0)
      metric = v2_free_metric()
      slug = context.project.slug
      query = metric_query(metric, slug, from, to)
      result = execute_query(context.conn, query, "getMetric")
      assert called(Metric.timeseries_data(metric, slug, from, to, :_, :_))
      assert result != nil
    end

    test "can access FREE queries for all time", context do
      {from, to} = from_to(2500, 0)
      slug = context.project.slug
      query = history_price_query(slug, from, to)
      result = execute_query(context.conn, query, "historyPrice")
      ticker_slug = context.project.ticker <> "_" <> slug
      assert_called(Sanbase.Prices.Store.fetch_prices_with_resolution(ticker_slug, from, to, :_))
      assert result != nil
    end

    test "can access RESTRICTED metrics for less than 7 years", context do
      {from, to} = from_to(7 * 365 - 1, 7 * 365 - 2)
      metric = v2_restricted_metric()
      slug = context.project.slug
      query = metric_query(metric, slug, from, to)
      result = execute_query(context.conn, query, "getMetric")

      assert called(Metric.timeseries_data(metric, slug, from, to, :_, :_))
      assert result != nil
    end

    test "can access RESTRICTED queries for less than 7 years", context do
      {from, to} = from_to(7 * 365 - 1, 7 * 365 - 2)
      query = network_growth_query(context.project.slug, from, to)
      result = execute_query(context.conn, query, "networkGrowth")
      contract = context.project.main_contract_address

      assert_called(Sanbase.Clickhouse.NetworkGrowth.network_growth(contract, from, to, :_))
      assert result != nil
    end

    test "cannot access RESTRICTED metrics for over 7 years", context do
      {from, to} = from_to(7 * 365 + 1, 7 * 365 - 1)
      metric = v2_restricted_metric()
      slug = context.project.slug
      query = metric_query(metric, slug, from, to)
      result = execute_query(context.conn, query, "getMetric")

      assert_called(Metric.timeseries_data(metric, slug, :_, :_, :_, :_))
      refute called(Metric.timeseries_data(metric, slug, from, to, :_, :_))
      assert result != nil
    end

    test "cannot access RESTRICTED queries for more than 7 years", context do
      {from, to} = from_to(7 * 365 + 1, 7 * 365 - 1)
      query = network_growth_query(context.project.slug, from, to)
      result = execute_query(context.conn, query, "networkGrowth")
      contract = context.project.main_contract_address

      refute called(Sanbase.Clickhouse.NetworkGrowth.network_growth(contract, from, to, :_))
      assert result != nil
    end

    test "can access RESTRICTED metrics realtime", context do
      {from, to} = from_to(10, 0)
      metric = v2_restricted_metric()
      slug = context.project.slug
      query = metric_query(metric, slug, from, to)
      result = execute_query(context.conn, query, "getMetric")

      assert called(Metric.timeseries_data(metric, slug, from, to, :_, :_))
      assert result != nil
    end

    test "can access RESTRICTED queries realtime", context do
      {from, to} = from_to(10, 0)
      query = network_growth_query(context.project.slug, from, to)
      result = execute_query(context.conn, query, "networkGrowth")
      contract = context.project.main_contract_address

      assert_called(Sanbase.Clickhouse.NetworkGrowth.network_growth(contract, from, to, :_))
      assert result != nil
    end
  end

  describe "SANApi product, user with PREMIUM plan" do
    setup context do
      insert(:subscription_premium, user: context.user)
      :ok
    end

    test "can access FREE metrics for all time", context do
      {from, to} = from_to(2500, 0)
      metric = v2_free_metric()
      slug = context.project.slug
      query = metric_query(metric, slug, from, to)
      result = execute_query(context.conn, query, "getMetric")
      assert_called(Metric.timeseries_data(metric, slug, from, to, :_, :_))
      assert result != nil
    end

    test "can access FREE queries for all time", context do
      {from, to} = from_to(2500, 0)
      slug = context.project.slug
      query = history_price_query(slug, from, to)
      result = execute_query(context.conn, query, "historyPrice")
      ticker_slug = context.project.ticker <> "_" <> slug
      assert_called(Sanbase.Prices.Store.fetch_prices_with_resolution(ticker_slug, from, to, :_))
      assert result != nil
    end

    test "can access RESTRICTED metrics for all time & realtime", context do
      {from, to} = from_to(2500, 0)
      metric = v2_restricted_metric()
      slug = context.project.slug
      query = metric_query(metric, slug, from, to)
      result = execute_query(context.conn, query, "getMetric")
      assert_called(Metric.timeseries_data(metric, slug, from, to, :_, :_))
      assert result != nil
    end

    test "can access RESTRICTED queries for all time & realtime", context do
      {from, to} = from_to(2500, 0)
      query = network_growth_query(context.project.slug, from, to)
      result = execute_query(context.conn, query, "networkGrowth")
      contract = context.project.main_contract_address

      assert_called(Sanbase.Clickhouse.NetworkGrowth.network_growth(contract, from, to, :_))
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

  defp metric_query(metric, slug, from, to) do
    """
      {
        getMetric(metric: "#{metric}") {
          timeseriesData(slug: "#{slug}", from: "#{from}", to: "#{to}", interval: "30d"){
            datetime
            value
          }
        }
      }
    """
  end

  defp daily_active_deposits_query(slug, from, to) do
    """
      {
        dailyActiveDeposits(slug: "#{slug}", from: "#{from}", to: "#{to}", interval: "1d"){
          datetime
          activeDeposits
        }
      }
    """
  end

  defp network_growth_query(slug, from, to) do
    """
      {
        networkGrowth(slug: "#{slug}", from: "#{from}", to: "#{to}", interval: "1d"){
          datetime
          newAddresses
        }
      }
    """
  end

  defp history_price_query(slug, from, to) do
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
       [from_iso8601!("2019-01-01T00:00:00Z"), 20, 0.2, 20_000, 2500]
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
