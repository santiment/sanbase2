defmodule Sanbase.Billing.SanbaseProductAccessTest do
  use SanbaseWeb.ConnCase, async: false

  import Mock
  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.TestHelpers

  alias Sanbase.Metric
  alias Sanbase.Signal

  @triggers_limit_count 10
  @product "SANBASE"

  setup_all_with_mocks([
    {Sanbase.Price, [:passthrough], [timeseries_data: fn _, _, _, _ -> price_resp() end]},
    {Sanbase.Metric, [:passthrough], [timeseries_data: fn _, _, _, _, _, _ -> metric_resp() end]},
    {Sanbase.Signal, [:passthrough], [timeseries_data: fn _, _, _, _, _, _ -> signal_resp() end]},
    {Sanbase.Alert.UserTrigger, [:passthrough],
     [triggers_count_for: fn _ -> @triggers_limit_count end]}
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
      query = network_growth_query(slug, from, to)

      result = execute_query(context.conn, query, "networkGrowth")

      assert_called(Metric.timeseries_data("network_growth", :_, :_, :_, :_, :_))
      refute called(Metric.timeseries_data("network_growth", :_, from, to, :_, :_))
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
      query = network_growth_query(slug, from, to)

      result = execute_query(context.conn, query, "networkGrowth")

      refute called(Metric.timeseries_data("network_growth", :_, from, to, :_, :_))
      assert result != nil
    end

    test "cannot access RESTRICTED queries for the past 30 days - both params outside allowed",
         context do
      {from, to} = from_to(20, 10)
      slug = context.project.slug
      query = network_growth_query(slug, from, to)

      result = execute_query_with_error(context.conn, query, "networkGrowth")

      refute called(Metric.timeseries_data("network_growth", :_, from, to, :_, :_))
      assert result != nil
    end

    test "can access RESTRICTED queries within 2 years and 30 day ago interval", context do
      {from, to} = from_to(2 * 365 - 2, 32)
      slug = context.project.slug
      query = network_growth_query(slug, from, to)

      result = execute_query(context.conn, query, "networkGrowth")

      assert_called(Metric.timeseries_data("network_growth", :_, from, to, :_, :_))
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

    # test "can access RESTRICTED signals for all time", context do
    #   {from, to} = from_to(4000, 10)
    #   slug = context.project.slug
    #   signal = restricted_signal_for_plan(context.next_integer.(), @product, "PRO")
    #   query = signal_query(signal, slug, from, to)

    #   result = execute_query(context.conn, query, "getSignal")

    #   assert_called(Signal.timeseries_data(signal, :_, from, to, :_, :_))
    #   assert result != nil
    # end

    test "can access RESTRICTED queries for all time", context do
      {from, to} = from_to(4000, 10)
      slug = context.project.slug
      query = network_growth_query(slug, from, to)

      result = execute_query(context.conn, query, "networkGrowth")

      assert_called(Metric.timeseries_data("network_growth", :_, from, to, :_, :_))
      assert result != nil
    end

    test "can access RESTRICTED metrics realtime", context do
      {from, to} = from_to(10, 0)
      slug = context.project.slug
      query = network_growth_query(slug, from, to)

      result = execute_query(context.conn, query, "networkGrowth")

      assert_called(Metric.timeseries_data("network_growth", :_, from, to, :_, :_))
      assert result != nil
    end

    test "can access RESTRICTED queries realtime", context do
      {from, to} = from_to(10, 0)
      slug = context.project.slug
      query = network_growth_query(slug, from, to)

      result = execute_query(context.conn, query, "networkGrowth")

      assert_called(Metric.timeseries_data("network_growth", :_, from, to, :_, :_))
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
      query = network_growth_query(slug, from, to)

      result = execute_query(context.conn, query, "networkGrowth")

      assert_called(Metric.timeseries_data("network_growth", :_, from, to, :_, :_))
      assert result != nil
    end
  end

  describe "for SANbase when alerts limit reached" do
    test "user with BASIC plan can create new trigger", context do
      insert(:subscription_pro_sanbase, user: context.user)

      assert create_trigger_mutation(context)["trigger"]["id"] != nil
    end

    test "user with PRO plan can create new trigger", context do
      insert(:subscription_pro_sanbase, user: context.user)

      assert create_trigger_mutation(context)["trigger"]["id"] != nil
    end
  end

  # describe "for FREE plan when alerts limits not reached" do
  #   # Override the setup_all mock
  #   setup_with_mocks([
  #     {UserTrigger, [:passthrough], [triggers_count_for: fn _ -> @triggers_limit_count - 1 end]}
  #   ]) do
  #     []
  #   end

  #   test "user can create new trigger", context do
  #     assert create_trigger_mutation(context)["trigger"]["id"] != nil
  #   end
  # end

  # Private functions

  defp create_trigger_mutation(context) do
    query = create_trigger_mutation()

    execute_mutation(context.conn, query, "createTrigger")
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

  defp metric_resp() do
    {:ok,
     [
       %{value: 10.0, datetime: ~U[2019-01-01 00:00:00Z]},
       %{value: 20.0, datetime: ~U[2019-01-02 00:00:00Z]}
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

  defp create_trigger_mutation() do
    trigger_settings = %{
      type: "metric_signal",
      metric: "active_addresses_24h",
      target: %{slug: "santiment"},
      channel: "telegram",
      time_window: "1d",
      operation: %{percent_up: 200.0}
    }

    trigger_settings_json = trigger_settings |> Jason.encode!()

    ~s|
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
  |
    |> format_interpolated_json()
  end

  defp format_interpolated_json(string) do
    string
    |> String.replace(~r|\"|, ~S|\\"|)
    |> String.replace(~r|'|, ~S|"|)
  end
end
