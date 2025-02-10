defmodule Sanbase.Billing.SanbaseProductAccessTest do
  use SanbaseWeb.ConnCase, async: false

  import Mock
  import Sanbase.Factory
  import Sanbase.TestHelpers
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Alert.UserTrigger
  alias Sanbase.Clickhouse.TopHolders
  alias Sanbase.Metric
  alias Sanbase.Signal

  @triggers_free_limit_count 3
  @triggers_pro_limit_count 20
  @triggers_max_business_limit_count 50

  @product "SANBASE"

  setup_all_with_mocks([
    {Sanbase.Price, [:passthrough], [timeseries_data: fn _, _, _, _ -> price_resp() end]},
    {Sanbase.Metric, [:passthrough], [timeseries_data: fn _, _, _, _, _, _ -> metric_resp() end]},
    {Sanbase.Signal, [:passthrough], [timeseries_data: fn _, _, _, _, _, _ -> signal_resp() end]},
    {TopHolders, [], [top_holders: fn _, _, _, _ -> top_holders_resp() end]},
    {UserTrigger, [:passthrough], [triggers_count_for: fn _ -> @triggers_free_limit_count end]}
  ]) do
    []
  end

  setup do
    user = insert(:user)
    project = insert(:random_erc20_project)

    conn = setup_jwt_auth(build_conn(), user)

    [user: user, conn: conn, project: project]
  end

  describe "SANBase product, No subscription" do
    test "can access FREE metrics for all time", context do
      {from, to} = from_to(2500, 0)
      slug = context.project.slug

      metric = get_free_timeseries_element(context.next_integer.(), @product, :metric)
      selector = %{slug: slug}
      query = metric_query(metric, selector, from, to)

      result = execute_query(context.conn, query, "getMetric")

      assert_called(Metric.timeseries_data(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "can access FREE queries for all time", context do
      {from, to} = from_to(2500, 0)
      query = history_price_query(context.project, from, to)

      result = execute_query(context.conn, query, "historyPrice")

      assert_called(Sanbase.Price.timeseries_data(:_, from, to, :_))
      assert result != nil
    end

    test "can access FREE signals for all time", context do
      {from, to} = from_to(2500, 0)
      slug = context.project.slug

      signal = get_free_timeseries_element(context.next_integer.(), @product, :signal)
      query = signal_query(signal, slug, from, to)

      result = execute_query(context.conn, query, "getSignal")

      assert_called(Signal.timeseries_data(signal, :_, from, to, :_, :_))
      assert result != nil
    end

    test "cannot access RESTRICTED metrics for over 2 years", context do
      {from, to} = from_to(2 * 365 + 1, 31)
      slug = context.project.slug
      metric = v2_restricted_metric_for_plan(context.next_integer.(), @product, "FREE")
      selector = %{slug: slug}
      query = metric_query(metric, selector, from, to)

      result = execute_query(context.conn, query, "getMetric")

      assert_called(Metric.timeseries_data(metric, :_, :_, :_, :_, :_))
      refute called(Metric.timeseries_data(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "cannot access RESTRICTED queries for over 2 years", context do
      {from, to} = from_to(2 * 365 + 1, 31)
      slug = context.project.slug
      query = restricted_access_query(slug, from, to)

      result = execute_query(context.conn, query)

      assert_called(TopHolders.top_holders(slug, :_, :_, :_))
      refute called(TopHolders.top_holders(slug, from, to, :_))
      assert result != nil
    end

    test "cannot access RESTRICTED metrics for the past 30 days", context do
      {from, to} = from_to(32, 28)
      slug = context.project.slug
      metric = v2_restricted_metric_for_plan(context.next_integer.(), @product, "FREE")
      selector = %{slug: slug}
      query = metric_query(metric, selector, from, to)

      result = execute_query(context.conn, query, "getMetric")

      refute called(Metric.timeseries_data(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "cannot access RESTRICTED metrics for the past 30 days - both params outside allowed",
         context do
      {from, to} = from_to(20, 10)
      slug = context.project.slug

      metric = v2_restricted_metric_for_plan(context.next_integer.(), @product, "FREE")

      selector = %{slug: slug}
      query = metric_query(metric, selector, from, to)

      result = execute_query_with_error(context.conn, query, "getMetric")

      refute called(Metric.timeseries_data(metric, :_, :_, :_, :_, :_))
      assert result != nil
    end

    test "cannot access RESTRICTED queries for the past 30 days", context do
      {from, to} = from_to(31, 29)
      slug = context.project.slug
      query = restricted_access_query(slug, from, to)
      result = execute_query(context.conn, query)

      refute called(TopHolders.top_holders(slug, from, to, :_))
      assert result != nil
    end

    test "cannot access RESTRICTED queries for the past 30 days - both params outside allowed",
         context do
      {from, to} = from_to(20, 10)
      slug = context.project.slug
      query = restricted_access_query(slug, from, to)
      result = execute_query_with_error(context.conn, query)

      refute called(TopHolders.top_holders(slug, from, to, :_))
      assert result != nil
    end

    test "can access RESTRICTED queries within 2 years and 30 day ago interval", context do
      {from, to} = from_to(2 * 365 - 2, 32)
      slug = context.project.slug
      query = restricted_access_query(slug, from, to)

      result = execute_query(context.conn, query)

      assert_called(TopHolders.top_holders(slug, from, to, :_))
      assert result != nil
    end

    test "can access RESTRICTED metrics within 2 years and 30 day ago interval", context do
      {from, to} = from_to(2 * 365 - 2, 32)
      slug = context.project.slug
      metric = v2_restricted_metric_for_plan(context.next_integer.(), @product, "FREE")
      selector = %{slug: slug}
      query = metric_query(metric, selector, from, to)

      result = execute_query(context.conn, query, "getMetric")

      assert_called(Metric.timeseries_data(metric, :_, from, to, :_, :_))
      assert result != nil
    end
  end

  describe "SANBase product, user with PRO plan" do
    setup context do
      insert(:subscription_pro_sanbase, user: context.user)
      :ok
    end

    test "can access FREE metrics for all time", context do
      {from, to} = from_to(4000, 0)
      slug = context.project.slug
      metric = get_free_timeseries_element(context.next_integer.(), @product, :metric)
      selector = %{slug: slug}
      query = metric_query(metric, selector, from, to)

      result = execute_query(context.conn, query, "getMetric")

      assert_called(Metric.timeseries_data(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "can access FREE queries for all time", context do
      {from, to} = from_to(4000, 0)
      query = history_price_query(context.project, from, to)

      result = execute_query(context.conn, query, "historyPrice")

      assert_called(Sanbase.Price.timeseries_data(:_, from, to, :_))
      assert result != nil
    end

    test "can access FREE signals for all time", context do
      {from, to} = from_to(2500, 0)
      slug = context.project.slug

      signal = get_free_timeseries_element(context.next_integer.(), @product, :signal)
      query = signal_query(signal, slug, from, to)

      result = execute_query(context.conn, query, "getSignal")

      assert_called(Signal.timeseries_data(signal, :_, from, to, :_, :_))
      assert result != nil
    end

    test "can access RESTRICTED metrics for all time", context do
      {from, to} = from_to(4000, 10)
      slug = context.project.slug
      metric = v2_restricted_metric_for_plan(context.next_integer.(), @product, "PRO")
      selector = %{slug: slug}
      query = metric_query(metric, selector, from, to)

      result = execute_query(context.conn, query, "getMetric")

      assert_called(Metric.timeseries_data(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "can access RESTRICTED queries for all time", context do
      {from, to} = from_to(4000, 10)
      slug = context.project.slug
      query = restricted_access_query(slug, from, to)

      result = execute_query(context.conn, query)

      assert_called(TopHolders.top_holders(slug, from, to, :_))
      assert result != nil
    end

    test "can access RESTRICTED metrics realtime", context do
      {from, to} = from_to(10, 0)
      slug = context.project.slug
      query = restricted_access_query(slug, from, to)

      result = execute_query(context.conn, query)

      assert_called(TopHolders.top_holders(slug, from, to, :_))
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
  end

  describe "SANBase product, user with PRO PLUS plan" do
    setup context do
      insert(:subscription_pro_plus_sanbase, user: context.user)
      :ok
    end

    test "can access RESTRICTED metrics realtime", context do
      {from, to} = from_to(10, 0)
      slug = context.project.slug
      query = restricted_access_query(slug, from, to)

      result = execute_query(context.conn, query)

      assert_called(TopHolders.top_holders(slug, from, to, :_))
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

        "SANAPI_PRO" ->
          user = insert(:user, email: "sanapi_pro@example.com")
          insert(:subscription_pro, user: user)
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

    jwt_conn = setup_jwt_auth(build_conn(), user)

    %{user: user, jwt_conn: jwt_conn}
  end

  describe "API access V2 plans" do
    test "FREE 30 days realtime cutoff API access", context do
      data = setup_subscription("FREE")
      {from, to} = from_to(2 * 360, 31)
      metric = "mean_age"
      slug = context.project.slug
      selector = %{slug: slug}
      query = metric_query(metric, selector, from, to)
      result = execute_query(data.jwt_conn, query, "getMetric")
      assert_called(Metric.timeseries_data(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "FREE plan cannot access more than 2 years historical data", context do
      data = setup_subscription("FREE")
      {from, to} = from_to(2 * 365 + 1, 31)
      metric = "mean_age"
      slug = context.project.slug
      selector = %{slug: slug}
      query = metric_query(metric, selector, from, to)
      result = execute_query(data.jwt_conn, query, "getMetric")
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
      result = execute_query(data.jwt_conn, query, "getMetric")
      assert_called(Metric.timeseries_data(metric, :_, :_, :_, :_, :_))
      refute called(Metric.timeseries_data(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "Sanbase PRO has no restrictions", context do
      data = setup_subscription("SANBASE_PRO")
      {from, to} = from_to(3 * 360, 1)
      metric = "mean_age"
      slug = context.project.slug
      selector = %{slug: slug}
      query = metric_query(metric, selector, from, to)
      result = execute_query(data.jwt_conn, query, "getMetric")
      assert_called(Metric.timeseries_data(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "Sanbase MAX has no restrictions", context do
      data = setup_subscription("SANBASE_MAX")
      {from, to} = from_to(5 * 360, 1)
      metric = "mean_age"
      slug = context.project.slug
      selector = %{slug: slug}
      query = metric_query(metric, selector, from, to)
      result = execute_query(data.jwt_conn, query, "getMetric")
      assert_called(Metric.timeseries_data(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "Sanapi PRO has no restrictions", context do
      data = setup_subscription("SANAPI_PRO")
      {from, to} = from_to(5 * 360, 1)
      metric = "mean_age"
      slug = context.project.slug
      selector = %{slug: slug}
      query = metric_query(metric, selector, from, to)
      result = execute_query(data.jwt_conn, query, "getMetric")
      assert_called(Metric.timeseries_data(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "Business PRO has no restrictions", context do
      data = setup_subscription("BUSINESS_PRO")
      {from, to} = from_to(5 * 360, 1)
      metric = "mean_age"
      slug = context.project.slug
      selector = %{slug: slug}
      query = metric_query(metric, selector, from, to)
      result = execute_query(data.jwt_conn, query, "getMetric")
      assert_called(Metric.timeseries_data(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "Business MAX has restrictions", context do
      data = setup_subscription("BUSINESS_MAX")
      {from, to} = from_to(5 * 360, 1)
      metric = "mean_age"
      slug = context.project.slug
      selector = %{slug: slug}
      query = metric_query(metric, selector, from, to)
      result = execute_query(data.jwt_conn, query, "getMetric")
      assert_called(Metric.timeseries_data(metric, :_, from, to, :_, :_))
      assert result != nil
    end
  end

  describe "Triggers limits for FREE plan" do
    test "When limit not reached - user can create new trigger", _context do
      (&UserTrigger.triggers_count_for/1)
      |> Sanbase.Mock.prepare_mock2(@triggers_free_limit_count - 1)
      |> Sanbase.Mock.run_with_mocks(fn ->
        data = setup_subscription("FREE")
        assert create_trigger_mutation(data.jwt_conn)["trigger"]["id"] != nil
      end)
    end

    test "When limit reached - user cannot create new trigger", _context do
      (&UserTrigger.triggers_count_for/1)
      |> Sanbase.Mock.prepare_mock2(@triggers_free_limit_count)
      |> Sanbase.Mock.run_with_mocks(fn ->
        data = setup_subscription("FREE")
        assert create_trigger_mutation(data.jwt_conn)["trigger"]["id"] == nil
      end)
    end
  end

  describe "Triggers limits for PRO plan" do
    test "When limit not reached - user can create new trigger", _context do
      (&UserTrigger.triggers_count_for/1)
      |> Sanbase.Mock.prepare_mock2(@triggers_pro_limit_count - 1)
      |> Sanbase.Mock.run_with_mocks(fn ->
        data = setup_subscription("SANBASE_PRO")
        assert create_trigger_mutation(data.jwt_conn)["trigger"]["id"] != nil
      end)
    end

    test "When limit reached - user cannot create new trigger", _context do
      (&UserTrigger.triggers_count_for/1)
      |> Sanbase.Mock.prepare_mock2(@triggers_pro_limit_count)
      |> Sanbase.Mock.run_with_mocks(fn ->
        data = setup_subscription("SANBASE_PRO")
        assert create_trigger_mutation(data.jwt_conn)["trigger"]["id"] == nil
      end)
    end
  end

  describe "Triggers limits for Sanbase MAX plan" do
    test "When limit not reached - user can create new trigger", _context do
      (&UserTrigger.triggers_count_for/1)
      |> Sanbase.Mock.prepare_mock2(@triggers_max_business_limit_count - 1)
      |> Sanbase.Mock.run_with_mocks(fn ->
        data = setup_subscription("SANBASE_MAX")
        assert create_trigger_mutation(data.jwt_conn)["trigger"]["id"] != nil
      end)
    end

    test "When limit reached - user cannot create new trigger", _context do
      (&UserTrigger.triggers_count_for/1)
      |> Sanbase.Mock.prepare_mock2(@triggers_max_business_limit_count)
      |> Sanbase.Mock.run_with_mocks(fn ->
        data = setup_subscription("SANBASE_MAX")
        assert create_trigger_mutation(data.jwt_conn)["trigger"]["id"] == nil
      end)
    end
  end

  describe "Triggers limits for BUSINESS PRO plan" do
    test "When limit not reached - user can create new trigger", _context do
      (&UserTrigger.triggers_count_for/1)
      |> Sanbase.Mock.prepare_mock2(@triggers_max_business_limit_count - 1)
      |> Sanbase.Mock.run_with_mocks(fn ->
        data = setup_subscription("BUSINESS_PRO")
        assert create_trigger_mutation(data.jwt_conn)["trigger"]["id"] != nil
      end)
    end

    test "When limit reached - user cannot create new trigger", _context do
      (&UserTrigger.triggers_count_for/1)
      |> Sanbase.Mock.prepare_mock2(@triggers_max_business_limit_count)
      |> Sanbase.Mock.run_with_mocks(fn ->
        data = setup_subscription("BUSINESS_PRO")
        assert create_trigger_mutation(data.jwt_conn)["trigger"]["id"] == nil
      end)
    end
  end

  describe "Triggers limits for BUSINESS MAX plan" do
    test "When limit not reached - user can create new trigger", _context do
      (&UserTrigger.triggers_count_for/1)
      |> Sanbase.Mock.prepare_mock2(@triggers_max_business_limit_count - 1)
      |> Sanbase.Mock.run_with_mocks(fn ->
        data = setup_subscription("BUSINESS_MAX")
        assert create_trigger_mutation(data.jwt_conn)["trigger"]["id"] != nil
      end)
    end

    test "When limit reached - user cannot create new trigger", _context do
      (&UserTrigger.triggers_count_for/1)
      |> Sanbase.Mock.prepare_mock2(@triggers_max_business_limit_count)
      |> Sanbase.Mock.run_with_mocks(fn ->
        data = setup_subscription("BUSINESS_MAX")
        assert create_trigger_mutation(data.jwt_conn)["trigger"]["id"] == nil
      end)
    end
  end

  # Private functions

  defp create_trigger_mutation(conn) do
    query = create_trigger_mutation()

    execute_mutation(conn, query, "createTrigger")
  end

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

  defp history_price_query(project, from, to) do
    """
      {
        historyPrice(slug: "#{project.slug}", from: "#{from}", to: "#{to}", interval: "30d"){
          datetime
          priceUsd
        }
      }
    """
  end

  defp metric_resp do
    {:ok,
     [
       %{value: 10.0, datetime: ~U[2019-01-01 00:00:00Z]},
       %{value: 20.0, datetime: ~U[2019-01-02 00:00:00Z]}
     ]}
  end

  defp signal_resp do
    {:ok,
     [
       %{value: 5.0, datetime: ~U[2020-01-01 00:00:00Z]},
       %{value: 10.0, datetime: ~U[2020-01-02 00:00:00Z]}
     ]}
  end

  defp price_resp do
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

  defp top_holders_resp do
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

  defp create_trigger_mutation do
    trigger_settings = %{
      type: "metric_signal",
      metric: "active_addresses_24h",
      target: %{slug: "santiment"},
      channel: "telegram",
      time_window: "1d",
      operation: %{percent_up: 200.0}
    }

    trigger_settings_json = Jason.encode!(trigger_settings)

    format_interpolated_json(~s"""
     mutation {
       createTrigger(
         settings: '#{trigger_settings_json}'
         title: 'Generic title'
         cooldown: '23h'
       ) {
         trigger{
           id
           cooldown
           settings
         }
       }
     }
    """)
  end

  defp format_interpolated_json(string) do
    string
    |> String.replace(~r|\"|, ~S|\\"|)
    |> String.replace(~r|'|, ~S|"|)
  end
end
