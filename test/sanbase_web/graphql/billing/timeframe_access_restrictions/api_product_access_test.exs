defmodule Sanbase.Billing.ApiProductAccessTest do
  use SanbaseWeb.ConnCase

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers
  import Mock

  alias Sanbase.Auth.Apikey
  alias Sanbase.Metric

  @product "SANAPI"

  setup_with_mocks([
    {Sanbase.Price, [], [timeseries_data: fn _, _, _, _ -> price_resp() end]},
    {Metric, [:passthrough], [timeseries_data: fn _, _, _, _, _, _ -> metric_resp() end]}
  ]) do
    user = insert(:user)
    project = insert(:random_erc20_project)

    {:ok, apikey} = Apikey.generate_apikey(user)
    conn = setup_apikey_auth(build_conn(), apikey)

    [user: user, conn: conn, project: project]
  end

  describe "SanAPI product, No subscription" do
    test "can access FREE metrics for all time", context do
      {from, to} = from_to(2500, 0)
      metric = v2_free_metric(context.next_integer.())
      slug = context.project.slug
      query = metric_query(metric, slug, from, to)
      result = execute_query(context.conn, query, "getMetric")
      assert_called(Metric.timeseries_data(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "can access FREE queries for all time", context do
      {from, to} = from_to(2500, 0)
      slug = context.project.slug
      query = history_price_query(slug, from, to)
      result = execute_query(context.conn, query, "historyPrice")
      assert_called(Sanbase.Price.timeseries_data(slug, from, to, :_))
      assert result != nil
    end

    test "cannot access RESTRICTED metrics for over 3 months", context do
      {from, to} = from_to(91, 10)
      metric = v2_restricted_metric_for_plan(context.next_integer.(), @product, :free)
      slug = context.project.slug
      query = metric_query(metric, slug, from, to)
      result = execute_query(context.conn, query, "getMetric")

      assert_called(Metric.timeseries_data(metric, :_, :_, :_, :_, :_))
      refute called(Metric.timeseries_data(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "cannot access RESTRICTED queries for over 3 months", context do
      {from, to} = from_to(91, 10)
      query = network_growth_query(context.project.slug, from, to)
      result = execute_query(context.conn, query, "networkGrowth")

      refute called(Metric.timeseries_data("network_growth", :_, from, to, :_, :_))
      assert result != nil
    end

    test "cannot access RESTRICTED queries realtime", context do
      {from, to} = from_to(10, 0)
      query = network_growth_query(context.project.slug, from, to)
      result = execute_query(context.conn, query, "networkGrowth")

      refute called(Metric.timeseries_data("network_growth", :_, from, to, :_, :_))
      assert result != nil
    end

    test "can access RESTRICTED metrics within 90 days and 2 day interval", context do
      {from, to} = from_to(89, 2)
      metric = v2_restricted_metric_for_plan(context.next_integer.(), @product, :free)
      slug = context.project.slug
      query = metric_query(metric, slug, from, to)
      result = execute_query(context.conn, query, "getMetric")

      assert called(Metric.timeseries_data(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "can access RESTRICTED queries within 90 days and 2 day interval", context do
      {from, to} = from_to(89, 2)
      query = network_growth_query(context.project.slug, from, to)
      result = execute_query(context.conn, query, "networkGrowth")

      assert_called(Metric.timeseries_data("network_growth", :_, :_, :_, :_, :_))
      assert result != nil
    end
  end

  describe "SanAPI product, user with BASIC plan" do
    setup context do
      insert(:subscription_essential, user: context.user)
      :ok
    end

    test "can access FREE metrics for all time", context do
      {from, to} = from_to(2500, 0)
      metric = v2_free_metric(context.next_integer.())
      slug = context.project.slug
      query = metric_query(metric, slug, from, to)
      result = execute_query(context.conn, query, "getMetric")
      assert called(Metric.timeseries_data(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "can access FREE queries for all time", context do
      {from, to} = from_to(2500, 0)
      slug = context.project.slug
      query = history_price_query(slug, from, to)
      result = execute_query(context.conn, query, "historyPrice")
      assert_called(Sanbase.Price.timeseries_data(slug, from, to, :_))
      assert result != nil
    end

    test "can access RESTRICTED metrics for less than 2 years", context do
      {from, to} = from_to(2 * 365 - 1, 2 * 365 - 2)

      metric = v2_restricted_metric_for_plan(context.next_integer.(), @product, :basic)

      slug = context.project.slug
      query = metric_query(metric, slug, from, to)
      result = execute_query(context.conn, query, "getMetric")

      assert called(Metric.timeseries_data(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "can access RESTRICTED queries for less than 2 years", context do
      {from, to} = from_to(2 * 365 - 1, 2 * 365 - 2)
      query = network_growth_query(context.project.slug, from, to)
      result = execute_query(context.conn, query, "networkGrowth")

      assert_called(Metric.timeseries_data("network_growth", :_, :_, :_, :_, :_))
      assert result != nil
    end

    test "cannot access RESTRICTED queries for more than 2 years", context do
      {from, to} = from_to(2 * 365 + 1, 2 * 365 - 1)
      query = network_growth_query(context.project.slug, from, to)
      result = execute_query(context.conn, query, "networkGrowth")

      refute called(Metric.timeseries_data("network_growth", :_, from, to, :_, :_))
      assert result != nil
    end

    test "cannot access RESTRICTED metrics for more than 2 years", context do
      {from, to} = from_to(2 * 365 + 1, 2 * 365 - 1)
      metric = v2_restricted_metric_for_plan(context.next_integer.(), @product, :basic)
      slug = context.project.slug
      query = metric_query(metric, slug, from, to)
      result = execute_query(context.conn, query, "getMetric")

      assert_called(Metric.timeseries_data(metric, :_, :_, :_, :_, :_))
      refute called(Metric.timeseries_data(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "cannot access RESTRICTED metrics for more than 2 years - both params outside allowed",
         context do
      {from, to} = from_to(2 * 365 - 10, 2 * 365 - 2)
      metric = v2_restricted_metric_for_plan(context.next_integer.(), @product, :basic)
      slug = context.project.slug
      query = metric_query(metric, slug, from, to)
      result = execute_query_with_error(context.conn, query, "getMetric")

      refute called(Metric.timeseries_data(metric, :_, :_, :_, :_, :_))
      assert result != nil
    end

    test "can access RESTRICTED metrics realtime", context do
      {from, to} = from_to(10, 0)
      metric = v2_restricted_metric_for_plan(context.next_integer.(), @product, :basic)
      slug = context.project.slug
      query = metric_query(metric, slug, from, to)
      result = execute_query(context.conn, query, "getMetric")

      assert called(Metric.timeseries_data(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "can access RESTRICTED queries realtime", context do
      {from, to} = from_to(10, 0)
      query = network_growth_query(context.project.slug, from, to)
      result = execute_query(context.conn, query, "networkGrowth")

      assert_called(Metric.timeseries_data("network_growth", :_, :_, :_, :_, :_))
      assert result != nil
    end

    test "can't access metric with min plan PRO", context do
      {from, to} = from_to(2 * 365 - 1, 2 * 365 - 2)
      metric = "mvrv_long_short_diff_usd"
      slug = context.project.slug
      query = metric_query(metric, slug, from, to)
      error_message = execute_query_with_error(context.conn, query, "getMetric")

      refute called(Metric.timeseries_data(metric, :_, from, to, :_, :_))

      assert error_message ==
               "The metric mvrv_long_short_diff_usd is not accessible with your current plan basic. Please upgrade to pro plan."
    end

    test "some metrics can be accessed only with free timeframe", context do
      {from, to} = from_to(89, 2)
      metric = "active_deposits"
      slug = context.project.slug
      query = metric_query(metric, slug, from, to)
      result = execute_query(context.conn, query, "getMetric")

      assert_called(Metric.timeseries_data(metric, :_, :_, :_, :_, :_))
      assert result != nil
    end

    test "some metrics can't be accessed with basic timeframe",
         context do
      {from, to} = from_to(2 * 365 - 1, 2 * 365 - 2)
      metric = "active_deposits"
      slug = context.project.slug
      query = metric_query(metric, slug, from, to)
      error_msg = execute_query_with_error(context.conn, query, "getMetric")

      refute called(Metric.timeseries_data(metric, :_, from, to, :_, :_))
      assert error_msg != nil
    end
  end

  describe "SanAPI product, user with PRO plan" do
    setup context do
      insert(:subscription_pro, user: context.user)
      :ok
    end

    test "can access FREE metrics for all time", context do
      {from, to} = from_to(2500, 0)
      metric = v2_free_metric(context.next_integer.())
      slug = context.project.slug
      query = metric_query(metric, slug, from, to)
      result = execute_query(context.conn, query, "getMetric")
      assert called(Metric.timeseries_data(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "can access FREE queries for all time", context do
      {from, to} = from_to(2500, 0)
      slug = context.project.slug
      query = history_price_query(slug, from, to)
      result = execute_query(context.conn, query, "historyPrice")
      assert_called(Sanbase.Price.timeseries_data(slug, from, to, :_))
      assert result != nil
    end

    test "can access RESTRICTED metrics for less than 7 years", context do
      {from, to} = from_to(7 * 365 - 1, 7 * 365 - 2)
      metric = v2_restricted_metric_for_plan(context.next_integer.(), @product, :pro)
      slug = context.project.slug
      query = metric_query(metric, slug, from, to)
      result = execute_query(context.conn, query, "getMetric")

      assert called(Metric.timeseries_data(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "can access RESTRICTED queries for less than 7 years", context do
      {from, to} = from_to(7 * 365 - 1, 7 * 365 - 2)
      query = network_growth_query(context.project.slug, from, to)
      result = execute_query(context.conn, query, "networkGrowth")

      assert_called(Metric.timeseries_data("network_growth", :_, from, to, :_, :_))
      assert result != nil
    end

    test "can access RESTRICTED metrics for over 7 years", context do
      {from, to} = from_to(7 * 365 + 1, 7 * 365 - 1)
      metric = v2_restricted_metric_for_plan(context.next_integer.(), @product, :pro)
      slug = context.project.slug
      query = metric_query(metric, slug, from, to)
      result = execute_query(context.conn, query, "getMetric")

      assert_called(Metric.timeseries_data(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "can access RESTRICTED queries for more than 7 years", context do
      {from, to} = from_to(7 * 365 + 1, 7 * 365 - 1)
      query = network_growth_query(context.project.slug, from, to)
      result = execute_query(context.conn, query, "networkGrowth")

      assert_called(Metric.timeseries_data("network_growth", :_, from, to, :_, :_))
      assert result != nil
    end

    test "can access RESTRICTED metrics realtime", context do
      {from, to} = from_to(10, 0)
      metric = v2_restricted_metric_for_plan(context.next_integer.(), @product, :pro)
      slug = context.project.slug
      query = metric_query(metric, slug, from, to)
      result = execute_query(context.conn, query, "getMetric")

      assert called(Metric.timeseries_data(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "can access RESTRICTED queries realtime", context do
      {from, to} = from_to(10, 0)
      query = network_growth_query(context.project.slug, from, to)
      result = execute_query(context.conn, query, "networkGrowth")

      assert_called(Metric.timeseries_data("network_growth", :_, from, to, :_, :_))
      assert result != nil
    end

    test "can access metric with min plan PRO", context do
      {from, to} = from_to(7 * 365 + 1, 7 * 365 - 1)
      metric = "mvrv_long_short_diff_usd"
      slug = context.project.slug
      query = metric_query(metric, slug, from, to)
      result = execute_query(context.conn, query, "getMetric")

      assert_called(Metric.timeseries_data(metric, :_, from, to, :_, :_))
      assert result != nil
    end
  end

  describe "SanAPI product, user with PREMIUM plan" do
    setup context do
      insert(:subscription_premium, user: context.user)
      :ok
    end

    test "can access FREE metrics for all time", context do
      {from, to} = from_to(2500, 0)
      metric = v2_free_metric(context.next_integer.())
      slug = context.project.slug
      query = metric_query(metric, slug, from, to)
      result = execute_query(context.conn, query, "getMetric")
      assert_called(Metric.timeseries_data(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "can access FREE queries for all time", context do
      {from, to} = from_to(2500, 0)
      slug = context.project.slug
      query = history_price_query(slug, from, to)
      result = execute_query(context.conn, query, "historyPrice")
      assert_called(Sanbase.Price.timeseries_data(slug, from, to, :_))
      assert result != nil
    end

    test "can access RESTRICTED metrics for all time & realtime", context do
      {from, to} = from_to(2500, 0)
      metric = v2_restricted_metric_for_plan(context.next_integer.(), @product, :premium)
      slug = context.project.slug
      query = metric_query(metric, slug, from, to)
      result = execute_query(context.conn, query, "getMetric")
      assert_called(Metric.timeseries_data(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "can access RESTRICTED queries for all time & realtime", context do
      {from, to} = from_to(2500, 0)
      query = network_growth_query(context.project.slug, from, to)
      result = execute_query(context.conn, query, "networkGrowth")

      assert_called(Metric.timeseries_data("network_growth", :_, :_, :_, :_, :_))
      assert result != nil
    end
  end

  # Private functions

  defp metric_query(metric, slug, from, to) do
    """
      {
        getMetric(metric: "#{metric}") {
          timeseriesData(
            slug: "#{slug}"
            from: "#{from}"
            to: "#{to}"
            interval: "30d"
            includeIncompleteData: true){
              datetime
              value
          }
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
       %{value: 10.0, datetime: ~U[2019-01-01 00:00:00Z]},
       %{value: 20.0, datetime: ~U[2019-01-02 00:00:00Z]}
     ]}
  end

  defp price_resp() do
    {:ok,
     [
       %{
         datetime: ~U[2019-01-01 00:00:00Z],
         price_usd: 10,
         price_btc: 0.1,
         marketcap: 10_000,
         marketcap_usd: 10_000,
         volume: 500,
         volume_usd: 500
       },
       %{
         datetime: ~U[2019-01-02 00:00:00Z],
         price_usd: 20,
         price_btc: 0.2,
         marketcap: 20_000,
         marketcap_usd: 20000,
         volume: 2500,
         volume_usd: 2500
       }
     ]}
  end
end
