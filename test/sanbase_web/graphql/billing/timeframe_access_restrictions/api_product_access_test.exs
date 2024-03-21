defmodule Sanbase.Billing.ApiProductAccessTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import Sanbase.TestHelpers
  import SanbaseWeb.Graphql.TestHelpers
  import Mock

  alias Sanbase.Accounts.Apikey
  alias Sanbase.Price
  alias Sanbase.Metric
  alias Sanbase.Signal
  alias Sanbase.Clickhouse.TopHolders

  @product "SANAPI"

  setup_all_with_mocks([
    {Price, [], [timeseries_data: fn _, _, _, _ -> price_resp() end]},
    {Metric, [:passthrough], [timeseries_data: fn _, _, _, _, _, _ -> metric_resp() end]},
    {TopHolders, [], [top_holders: fn _, _, _, _ -> top_holders_resp() end]},
    {Signal, [:passthrough], [timeseries_data: fn _, _, _, _, _, _ -> signal_resp() end]}
  ]) do
    []
  end

  setup do
    user = insert(:user)
    project = insert(:random_erc20_project)
    {:ok, apikey} = Apikey.generate_apikey(user)
    conn = setup_apikey_auth(build_conn(), apikey)

    [user: user, conn: conn, project: project]
  end

  describe "SanAPI product, No subscription" do
    test "can access FREE metrics for all time", context do
      {from, to} = from_to(2500, 0)
      metric = get_free_timeseries_element(context.next_integer.(), @product, :metric)
      slug = context.project.slug
      selector = %{slug: slug}
      query = metric_query(metric, selector, from, to)
      result = execute_query(context.conn, query, "getMetric")
      assert_called(Metric.timeseries_data(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "can access FREE queries for all time", context do
      {from, to} = from_to(2500, 0)
      slug = context.project.slug
      query = history_price_query(slug, from, to)
      result = execute_query(context.conn, query, "historyPrice")
      assert_called(Price.timeseries_data(slug, from, to, :_))
      assert result != nil
    end

    test "can access FREE signals for all time", context do
      {from, to} = from_to(2500, 0)
      signal = get_free_timeseries_element(context.next_integer.(), @product, :signal)
      slug = context.project.slug
      query = signal_query(signal, slug, from, to)
      result = execute_query(context.conn, query, "getSignal")
      assert_called(Signal.timeseries_data(signal, :_, from, to, :_, :_))
      assert result != nil
    end

    test "cannot access RESTRICTED metrics for over 1 year", context do
      {from, to} = from_to(1 * 365 + 1, 32)
      metric = v2_restricted_metric_for_plan(context.next_integer.(), @product, "FREE")
      slug = context.project.slug
      selector = %{slug: slug}
      query = metric_query(metric, selector, from, to)
      result = execute_query(context.conn, query, "getMetric")

      assert_called(Metric.timeseries_data(metric, :_, :_, :_, :_, :_))
      refute called(Metric.timeseries_data(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "cannot access RESTRICTED queries for over 1 year", context do
      slug = context.project.slug
      {from, to} = from_to(1 * 365 + 1, 32)
      query = restricted_access_query(slug, from, to)
      result = execute_query(context.conn, query)

      refute called(TopHolders.top_holders(slug, from, to, :_))
      assert result != nil
    end

    test "cannot access RESTRICTED queries last 30 days", context do
      {from, to} = from_to(31, 29)
      slug = context.project.slug
      query = restricted_access_query(slug, from, to)
      result = execute_query(context.conn, query)

      refute called(TopHolders.top_holders(slug, from, to, :_))
      assert result != nil
    end

    test "can access RESTRICTED metrics within 1 years and 30 days interval", context do
      {from, to} = from_to(1 * 365 - 1, 32)

      for _ <- 1..5 do
        metric = v2_restricted_metric_for_plan(context.next_integer.(), @product, "FREE")
        slug = context.project.slug
        selector = %{slug: slug}
        query = metric_query(metric, selector, from, to)
        result = execute_query(context.conn, query, "getMetric")

        assert_called(Metric.timeseries_data(metric, :_, from, to, :_, :_))
        assert result != nil
      end
    end

    test "can access RESTRICTED queries within 1 year and 30 days interval", context do
      {from, to} = from_to(1 * 365 - 1, 32)
      slug = context.project.slug
      query = restricted_access_query(slug, from, to)
      result = execute_query(context.conn, query)

      assert_called(TopHolders.top_holders(slug, from, to, :_))
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
      metric = get_free_timeseries_element(context.next_integer.(), @product, :metric)
      slug = context.project.slug
      selector = %{slug: slug}
      query = metric_query(metric, selector, from, to)
      result = execute_query(context.conn, query, "getMetric")
      assert called(Metric.timeseries_data(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "can access FREE queries for all time", context do
      {from, to} = from_to(2500, 0)
      slug = context.project.slug
      query = history_price_query(slug, from, to)
      result = execute_query(context.conn, query, "historyPrice")
      assert_called(Price.timeseries_data(slug, from, to, :_))
      assert result != nil
    end

    test "can access FREE signals for all time", context do
      {from, to} = from_to(2500, 0)
      signal = get_free_timeseries_element(context.next_integer.(), @product, :signal)
      slug = context.project.slug
      query = signal_query(signal, slug, from, to)
      result = execute_query(context.conn, query, "getSignal")
      assert_called(Signal.timeseries_data(signal, :_, from, to, :_, :_))
      assert result != nil
    end

    test "can access RESTRICTED metrics for less than 1 years", context do
      {from, to} = from_to(1 * 365 - 1, 1 * 365 - 2)

      metric = v2_restricted_metric_for_plan(context.next_integer.(), @product, :basic)

      slug = context.project.slug
      selector = %{slug: slug}
      query = metric_query(metric, selector, from, to)
      result = execute_query(context.conn, query, "getMetric")

      assert called(Metric.timeseries_data(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "can access RESTRICTED queries for less than 1 year", context do
      {from, to} = from_to(1 * 365 - 1, 1 * 365 - 2)
      slug = context.project.slug
      query = restricted_access_query(slug, from, to)
      result = execute_query(context.conn, query)

      assert_called(TopHolders.top_holders(slug, from, to, :_))
      assert result != nil
    end

    test "cannot access RESTRICTED queries for more than 1 year", context do
      {from, to} = from_to(1 * 365 + 1, 1 * 365 - 1)
      slug = context.project.slug
      query = restricted_access_query(context.project.slug, from, to)
      result = execute_query(context.conn, query)

      refute called(TopHolders.top_holders(slug, from, to, :_))
      assert_called(TopHolders.top_holders(slug, :_, :_, :_))
      assert result != nil
    end

    test "cannot access RESTRICTED metrics for more than 1 year", context do
      {from, to} = from_to(1 * 365 + 1, 1 * 365 - 1)
      metric = v2_restricted_metric_for_plan(context.next_integer.(), @product, :basic)
      slug = context.project.slug
      selector = %{slug: slug}
      query = metric_query(metric, selector, from, to)
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
      selector = %{slug: slug}
      query = metric_query(metric, selector, from, to)
      result = execute_query_with_error(context.conn, query, "getMetric")

      refute called(Metric.timeseries_data(metric, :_, :_, :_, :_, :_))
      assert result != nil
    end

    test "can access RESTRICTED metrics realtime", context do
      {from, to} = from_to(10, 0)
      metric = v2_restricted_metric_for_plan(context.next_integer.(), @product, :basic)
      slug = context.project.slug
      selector = %{slug: slug}
      query = metric_query(metric, selector, from, to)
      result = execute_query(context.conn, query, "getMetric")

      assert called(Metric.timeseries_data(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "can access RESTRICTED queries realtime", context do
      {from, to} = from_to(10, 0)
      slug = context.project.slug
      query = restricted_access_query(slug, from, to)
      result = execute_query(context.conn, query)

      assert_called(TopHolders.top_holders(slug, from, to, :_))
      assert result != nil
    end

    test "can't access metric with min plan PRO", context do
      {from, to} = from_to(2 * 365 - 1, 2 * 365 - 2)
      metric = "withdrawal_balance"
      slug = context.project.slug
      selector = %{slug: slug}
      query = metric_query(metric, selector, from, to)
      error_message = execute_query_with_error(context.conn, query, "getMetric")

      refute called(Metric.timeseries_data(metric, :_, from, to, :_, :_))

      assert error_message ==
               """
               The metric #{metric} is not accessible with the currently used \
               SANAPI BASIC subscription. Please upgrade to SANAPI PRO subscription \
               or a Custom Plan that has access to it.

               If you have a subscription for one product but attempt to fetch data using \
               another product, this error will still be shown. The data on SANBASE cannot \
               be fetched with a SANAPI subscription and vice versa.
               """
    end

    # test "can't access signal with min plan PRO", context do
    #   {from, to} = from_to(2 * 365 - 1, 2 * 365 - 2)
    #   signal = restricted_signal_for_plan(context.next_integer.(), @product, "PRO")
    #   slug = context.project.slug
    #   query = signal_query(signal, slug, from, to)
    #   error_message = execute_query_with_error(context.conn, query, "getSignal")

    #   refute called(Signal.timeseries_data(signal, :_, from, to, :_, :_))

    #   assert error_message ==
    #            """
    #            The signal #{signal} is not accessible with the currently used
    #            Sanapi Basic subscription. Please upgrade to Sanapi Pro subscription.

    #            If you have a subscription for one product but attempt to fetch data using
    #            another product, this error will still be shown. The data on Sanbase cannot
    #            be fetched with a Sanapi subscription and vice versa.
    #            """
    # end

    test "some metrics can be accessed only with free timeframe", context do
      {from, to} = from_to(89, 2)
      metric = "active_deposits"
      slug = context.project.slug
      selector = %{slug: slug}
      query = metric_query(metric, selector, from, to)
      result = execute_query(context.conn, query, "getMetric")

      assert_called(Metric.timeseries_data(metric, :_, :_, :_, :_, :_))
      assert result != nil
    end
  end

  describe "SanAPI product, user with PRO plan" do
    setup context do
      insert(:subscription_pro, user: context.user)
      :ok
    end

    test "can access FREE metrics for all time", context do
      {from, to} = from_to(2500, 0)
      metric = get_free_timeseries_element(context.next_integer.(), @product, :metric)
      slug = context.project.slug
      selector = %{slug: slug}
      query = metric_query(metric, selector, from, to)
      result = execute_query(context.conn, query, "getMetric")
      assert called(Metric.timeseries_data(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "can access FREE queries for all time", context do
      {from, to} = from_to(2500, 0)
      slug = context.project.slug
      query = history_price_query(slug, from, to)
      result = execute_query(context.conn, query, "historyPrice")
      assert_called(Price.timeseries_data(slug, from, to, :_))
      assert result != nil
    end

    test "can access FREE signals for all time", context do
      {from, to} = from_to(2500, 0)
      signal = get_free_timeseries_element(context.next_integer.(), @product, :signal)
      slug = context.project.slug
      query = signal_query(signal, slug, from, to)
      result = execute_query(context.conn, query, "getSignal")
      assert_called(Signal.timeseries_data(signal, :_, from, to, :_, :_))
      assert result != nil
    end

    test "can access RESTRICTED metrics for less than 7 years", context do
      {from, to} = from_to(7 * 365 - 1, 7 * 365 - 2)
      metric = v2_restricted_metric_for_plan(context.next_integer.(), @product, "PRO")
      slug = context.project.slug
      selector = %{slug: slug}
      query = metric_query(metric, selector, from, to)
      result = execute_query(context.conn, query, "getMetric")

      assert called(Metric.timeseries_data(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "can access RESTRICTED queries for less than 7 years", context do
      {from, to} = from_to(7 * 365 - 1, 7 * 365 - 2)
      slug = context.project.slug
      query = restricted_access_query(slug, from, to)
      result = execute_query(context.conn, query)

      assert_called(TopHolders.top_holders(slug, from, to, :_))
      assert result != nil
    end

    test "can access RESTRICTED metrics for over 7 years", context do
      {from, to} = from_to(7 * 365 + 1, 7 * 365 - 1)
      metric = v2_restricted_metric_for_plan(context.next_integer.(), @product, "PRO")
      slug = context.project.slug
      selector = %{slug: slug}
      query = metric_query(metric, selector, from, to)
      result = execute_query(context.conn, query, "getMetric")

      assert_called(Metric.timeseries_data(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "can access RESTRICTED queries for more than 7 years", context do
      {from, to} = from_to(7 * 365 + 1, 7 * 365 - 1)
      slug = context.project.slug
      query = restricted_access_query(slug, from, to)
      result = execute_query(context.conn, query)

      assert_called(TopHolders.top_holders(slug, from, to, :_))
      assert result != nil
    end

    test "can access RESTRICTED metrics realtime", context do
      {from, to} = from_to(10, 0)
      metric = v2_restricted_metric_for_plan(context.next_integer.(), @product, "PRO")
      slug = context.project.slug
      selector = %{slug: slug}
      query = metric_query(metric, selector, from, to)
      result = execute_query(context.conn, query, "getMetric")

      assert called(Metric.timeseries_data(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "can access RESTRICTED queries realtime", context do
      {from, to} = from_to(10, 0)
      slug = context.project.slug
      query = restricted_access_query(context.project.slug, from, to)
      result = execute_query(context.conn, query)

      assert_called(TopHolders.top_holders(slug, from, to, :_))
      assert result != nil
    end

    test "can access metric with min plan PRO", context do
      {from, to} = from_to(7 * 365 + 1, 7 * 365 - 1)
      metric = "mvrv_long_short_diff_usd"
      slug = context.project.slug
      selector = %{slug: slug}
      query = metric_query(metric, selector, from, to)
      result = execute_query(context.conn, query, "getMetric")

      assert_called(Metric.timeseries_data(metric, :_, from, to, :_, :_))
      assert result != nil
    end
  end

  describe "SanAPI product, user with CUSTOM plan" do
    setup context do
      insert(:subscription_custom, user: context.user)
      :ok
    end

    test "can access FREE metrics for all time", context do
      {from, to} = from_to(2500, 0)
      metric = get_free_timeseries_element(context.next_integer.(), @product, :metric)
      slug = context.project.slug
      selector = %{slug: slug}
      query = metric_query(metric, selector, from, to)
      result = execute_query(context.conn, query, "getMetric")
      assert_called(Metric.timeseries_data(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "can access FREE queries for all time", context do
      {from, to} = from_to(2500, 0)
      slug = context.project.slug
      query = history_price_query(slug, from, to)
      result = execute_query(context.conn, query, "historyPrice")
      assert_called(Price.timeseries_data(slug, from, to, :_))
      assert result != nil
    end

    test "can access FREE signals for all time", context do
      {from, to} = from_to(2500, 0)
      signal = get_free_timeseries_element(context.next_integer.(), @product, :signal)
      slug = context.project.slug
      query = signal_query(signal, slug, from, to)
      result = execute_query(context.conn, query, "getSignal")
      assert_called(Signal.timeseries_data(signal, :_, from, to, :_, :_))
      assert result != nil
    end

    test "can access RESTRICTED metrics for all time & realtime", context do
      {from, to} = from_to(2500, 0)
      metric = v2_restricted_metric_for_plan(context.next_integer.(), @product, "CUSTOM")
      slug = context.project.slug
      selector = %{slug: slug}
      query = metric_query(metric, selector, from, to)
      result = execute_query(context.conn, query, "getMetric")
      assert_called(Metric.timeseries_data(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "can access RESTRICTED queries for all time & realtime", context do
      {from, to} = from_to(2500, 0)
      slug = context.project.slug
      query = restricted_access_query(slug, from, to)
      result = execute_query(context.conn, query)

      assert_called(TopHolders.top_holders(slug, from, to, :_))
      assert result != nil
    end

    test "can access holders distributions for all time & realtime", context do
      {from, to} = from_to(2500, 0)
      metric = "holders_distribution_0.01_to_0.1"
      slug = context.project.slug
      selector = %{slug: slug}
      query = metric_query(metric, selector, from, to)
      result = execute_query(context.conn, query, "getMetric")
      assert_called(Metric.timeseries_data(metric, :_, from, to, :_, :_))
      assert result != nil
    end
  end

  defp setup_subscription(product_plan) do
    user =
      case product_plan do
        "SANBASE_PRO" ->
          user = insert(:user, email: "sanbase_pro@example.com")
          insert(:subscription_pro_sanbase, user: user)
          user

        "SANBASE_MAX" ->
          user = insert(:user, email: "sanbase_max@example.com")
          insert(:subscription_max_sanbase, user: user)
          user

        "BUSINESS_PRO" ->
          user = insert(:user, email: "business_pro@example.com")
          insert(:subscription_business_pro_monthly, user: user)
          user

        "BUSINESS_MAX" ->
          user = insert(:user, email: "business_max@example.com")
          insert(:subscription_business_max_monthly, user: user)
          user

        "FREE" ->
          insert(:user, email: "free@example.com")
      end

    {:ok, apikey} = Sanbase.Accounts.Apikey.generate_apikey(user)
    apikey_conn = setup_apikey_auth(build_conn(), apikey)

    %{user: user, apikey: apikey, apikey_conn: apikey_conn}
  end

  # V2 plans are the plans that remain and user can subscribe to - FREE, SANBASE_PRO, SANBASE_MAX, BUSINESS_PRO, BUSINESS_MAX
  # V1 plans are the plans that are deprecated and user can't subscribe to but still exist
  describe "API access V2 plans" do
    test "FREE has 1 year of historical data and 30 days realtime cutoff API access", context do
      data = setup_subscription("FREE")
      {from, to} = from_to(360, 31)
      metric = "mean_age"
      slug = context.project.slug
      selector = %{slug: slug}
      query = metric_query(metric, selector, from, to)
      result = execute_query(data.apikey_conn, query, "getMetric")
      assert_called(Metric.timeseries_data(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "FREE plan cannot access more than 365 days historical data", context do
      data = setup_subscription("FREE")
      {from, to} = from_to(366, 31)
      metric = "mean_age"
      slug = context.project.slug
      selector = %{slug: slug}
      query = metric_query(metric, selector, from, to)
      result = execute_query(data.apikey_conn, query, "getMetric")
      assert_called(Metric.timeseries_data(metric, :_, :_, :_, :_, :_))
      refute called(Metric.timeseries_data(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "FREE plan cannot access data more recent than 30 days", context do
      data = setup_subscription("FREE")
      {from, to} = from_to(364, 29)
      metric = "mean_age"
      slug = context.project.slug
      selector = %{slug: slug}
      query = metric_query(metric, selector, from, to)
      result = execute_query(data.apikey_conn, query, "getMetric")
      assert_called(Metric.timeseries_data(metric, :_, :_, :_, :_, :_))
      refute called(Metric.timeseries_data(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "Sanbase PRO has 1 years of historical data and 30 days realtime cutoff API access",
         context do
      data = setup_subscription("SANBASE_PRO")
      {from, to} = from_to(360, 31)
      metric = "mean_age"
      slug = context.project.slug
      selector = %{slug: slug}
      query = metric_query(metric, selector, from, to)
      result = execute_query(data.apikey_conn, query, "getMetric")
      assert_called(Metric.timeseries_data(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "Sanbase PRO plan cannot access more than 365 days historical data", context do
      data = setup_subscription("SANBASE_PRO")
      {from, to} = from_to(366, 31)
      metric = "mean_age"
      slug = context.project.slug
      selector = %{slug: slug}
      query = metric_query(metric, selector, from, to)
      result = execute_query(data.apikey_conn, query, "getMetric")
      assert_called(Metric.timeseries_data(metric, :_, :_, :_, :_, :_))
      refute called(Metric.timeseries_data(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "Sanbase PRO plan cannot access data more recent than 30 days", context do
      data = setup_subscription("SANBASE_PRO")
      {from, to} = from_to(364, 29)
      metric = "mean_age"
      slug = context.project.slug
      selector = %{slug: slug}
      query = metric_query(metric, selector, from, to)
      result = execute_query(data.apikey_conn, query, "getMetric")
      assert_called(Metric.timeseries_data(metric, :_, :_, :_, :_, :_))
      refute called(Metric.timeseries_data(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "Sanbase MAX has 2 years of historical data and no realtime cutoff API access",
         context do
      data = setup_subscription("SANBASE_MAX")
      {from, to} = from_to(2 * 360, 1)
      metric = "mean_age"
      slug = context.project.slug
      selector = %{slug: slug}
      query = metric_query(metric, selector, from, to)
      result = execute_query(data.apikey_conn, query, "getMetric")
      assert_called(Metric.timeseries_data(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "Sanbase MAX plan cannot access more than 2 years historical data", context do
      data = setup_subscription("SANBASE_MAX")
      {from, to} = from_to(2 * 365 + 1, 1)
      metric = "mean_age"
      slug = context.project.slug
      selector = %{slug: slug}
      query = metric_query(metric, selector, from, to)
      result = execute_query(data.apikey_conn, query, "getMetric")
      assert_called(Metric.timeseries_data(metric, :_, :_, :_, :_, :_))
      refute called(Metric.timeseries_data(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "Business PRO has 2 years of historical data and no realtime cutoff API access",
         context do
      data = setup_subscription("BUSINESS_PRO")
      {from, to} = from_to(2 * 360, 1)
      metric = "mean_age"
      slug = context.project.slug
      selector = %{slug: slug}
      query = metric_query(metric, selector, from, to)
      result = execute_query(data.apikey_conn, query, "getMetric")
      assert_called(Metric.timeseries_data(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "Business PRO plan cannot access more than 2 years historical data", context do
      data = setup_subscription("BUSINESS_PRO")
      {from, to} = from_to(2 * 365 + 1, 1)
      metric = "mean_age"
      slug = context.project.slug
      selector = %{slug: slug}
      query = metric_query(metric, selector, from, to)
      result = execute_query(data.apikey_conn, query, "getMetric")
      assert_called(Metric.timeseries_data(metric, :_, :_, :_, :_, :_))
      refute called(Metric.timeseries_data(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "Business MAX has not historica or realtime restrictions API access", context do
      data = setup_subscription("BUSINESS_MAX")
      {from, to} = from_to(5 * 360, 1)
      metric = "mean_age"
      slug = context.project.slug
      selector = %{slug: slug}
      query = metric_query(metric, selector, from, to)
      result = execute_query(data.apikey_conn, query, "getMetric")
      assert_called(Metric.timeseries_data(metric, :_, from, to, :_, :_))
      assert result != nil
    end
  end

  # Private functions

  defp metric_query(metric, selector, from, to) do
    selector = extend_selector_with_required_fields(metric, selector)

    """
      {
        getMetric(metric: "#{metric}") {
          timeseriesData(
            selector: #{map_to_input_object_str(selector)}
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

  defp signal_query(signal, slug, from, to) do
    """
      {
        getSignal(signal: "#{signal}") {
          timeseriesData(
            slug: "#{slug}"
            from: "#{from}"
            to: "#{to}"
            interval: "30d"){
              datetime
              value
          }
        }
      }
    """
  end

  defp restricted_access_query(slug, from, to) do
    """
      {
        topHolders(slug: "#{slug}", from: "#{from}", to: "#{to}"){
          datetime
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

  defp top_holders_resp() do
    {:ok,
     [
       %{
         value: 29_470_056.221214663,
         address: "0x00000000219ab540356cbb839cbe05303d7705fa",
         labels: [
           %{name: "Whale", origin: "santiment", metadata: ""},
           %{name: "Cex Withdrawal", origin: "santiment", metadata: ""},
           %{name: "Whale Usd Balance", origin: "santiment", metadata: ""},
           %{name: "Contract", origin: "santiment", metadata: ""},
           %{name: "Withdrawn From", origin: "santiment", metadata: "kucoin"}
         ],
         datetime: ~U[2023-09-07 00:00:00Z],
         part_of_total: 0.2363491088191249,
         value_usd: 48_178_498_145.437546
       }
     ]}
  end

  defp signal_resp() do
    {:ok,
     [
       %{value: 5.0, datetime: ~U[2020-01-01 00:00:00Z]},
       %{value: 10.0, datetime: ~U[2020-01-02 00:00:00Z]}
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
         marketcap_usd: 20_000,
         volume: 2500,
         volume_usd: 2500
       }
     ]}
  end
end
