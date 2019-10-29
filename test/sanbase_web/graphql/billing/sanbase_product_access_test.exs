defmodule Sanbase.Billing.SanbaseProductAccessTest do
  use SanbaseWeb.ConnCase

  import Mock
  import Sanbase.Factory
  import Sanbase.TestHelpers
  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.DateTimeUtils, only: [from_iso8601!: 1]

  alias Sanbase.Signal.UserTrigger
  alias Sanbase.Billing.Plan.SanbaseAccessChecker
  alias Sanbase.Metric

  @triggers_limit_count 10

  setup_all_with_mocks([
    {Sanbase.Prices.Store, [], [fetch_prices_with_resolution: fn _, _, _, _ -> price_resp() end]},
    {Sanbase.Clickhouse.DailyActiveDeposits, [],
     [active_deposits: fn _, _, _, _ -> daily_active_deposits_resp() end]},
    {Sanbase.Clickhouse.NetworkGrowth, [],
     [network_growth: fn _, _, _, _ -> network_growth_resp() end]},
    {Metric, [:passthrough], [get: fn _, _, _, _, _, _ -> metric_resp() end]},
    {UserTrigger, [:passthrough], [triggers_count_for: fn _ -> @triggers_limit_count end]}
  ]) do
    :ok
  end

  setup do
    user = insert(:user)
    project = insert(:random_project)

    conn = setup_jwt_auth(build_conn(), user)

    [user: user, conn: conn, project: project]
  end

  describe "SANBase product, No subscription" do
    test "can access FREE v2 clickhouse metrics for all time", context do
      {from, to} = from_to(1500, 0)
      metric = v2_free_metric()
      query = metric_query(metric, from, to)
      result = execute_query(context.conn, query, "getMetric")
      assert_called(Metric.get(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "cannot access RESTRICTED v2 clickhouse metrics for over 2 years", context do
      {from, to} = from_to(2 * 365 + 1, 31)
      metric = v2_restricted_metric()
      query = metric_query(metric, from, to)
      result = execute_query(context.conn, query, "getMetric")

      assert_called(Metric.get(metric, :_, :_, :_, :_, :_))
      refute called(Metric.get(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "cannot access RESTRICTED v2 clickhouse metrics for the past 30 days", context do
      {from, to} = from_to(32, 28)
      metric = v2_restricted_metric()
      query = metric_query(metric, from, to)
      result = execute_query(context.conn, query, "getMetric")

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

    test "cannot access BASIC metrics for over 2 years", context do
      {from, to} = from_to(2 * 365 + 1, 31)
      query = network_growth_query(from, to)
      result = execute_query(context.conn, query, "networkGrowth")

      refute called(Sanbase.Clickhouse.NetworkGrowth.network_growth(:_, from, to, :_))
      assert result != nil
    end

    test "cannot access BASIC metrics more than 30 days", context do
      {from, to} = from_to(31, 29)
      query = network_growth_query(from, to)
      result = execute_query(context.conn, query, "networkGrowth")

      refute called(Sanbase.Clickhouse.NetworkGrowth.network_growth(:_, from, to, :_))
      assert result != nil
    end

    test "can access BASIC metrics within 2 years and 30 day ago interval", context do
      {from, to} = from_to(2 * 365 - 1, 31)
      query = network_growth_query(from, to)
      result = execute_query(context.conn, query, "networkGrowth")

      assert_called(Sanbase.Clickhouse.NetworkGrowth.network_growth(:_, from, to, :_))
      assert result != nil
    end

    test "can access PRO metrics at all", context do
      {from, to} = from_to(34, 31)
      query = daily_active_deposits_query(from, to)
      result = execute_query(context.conn, query, "dailyActiveDeposits")

      assert_called(Sanbase.Clickhouse.DailyActiveDeposits.active_deposits(:_, from, to, :_))
      assert result != nil
    end

    test "fallbacks to API pro subscription if exists", context do
      insert(:subscription_pro, user: context.user)

      from = Timex.shift(Timex.now(), days: -(18 * 30 - 1))
      to = Timex.now()
      query = daily_active_deposits_query(from, to)
      result = execute_query(context.conn, query, "dailyActiveDeposits")

      assert_called(Sanbase.Clickhouse.DailyActiveDeposits.active_deposits(:_, from, to, :_))
      assert result != nil
    end

    test "fallbacks to PREMIUM subscription if exists", context do
      insert(:subscription_premium, user: context.user)
      {from, to} = from_to(18 * 30 + 1, 0)
      query = daily_active_deposits_query(from, to)
      result = execute_query(context.conn, query, "dailyActiveDeposits")

      assert_called(Sanbase.Clickhouse.DailyActiveDeposits.active_deposits(:_, from, to, :_))
      assert result != nil
    end
  end

  describe "SANBase product, user with BASIC plan" do
    setup context do
      insert(:subscription_basic_sanbase, user: context.user)
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

    test "can access RESTRICTED v2 clickhouse metrics for 1 year", context do
      {from, to} = from_to(12 * 30, 0)
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

    test "cannot access BASIC metrics for more than 3 years", context do
      {from, to} = from_to(3 * 365 + 1, 10)
      query = network_growth_query(from, to)
      result = execute_query(context.conn, query, "networkGrowth")

      refute called(Sanbase.Clickhouse.NetworkGrowth.network_growth(:_, from, to, :_))
      assert result != nil
    end

    test "can access BASIC metrics for less than 3 years", context do
      {from, to} = from_to(3 * 365 - 1, 10)
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

    test "cannot access PRO metrics for more than 3 years", context do
      {from, to} = from_to(3 * 365 + 1, 10)
      query = daily_active_deposits_query(from, to)
      result = execute_query(context.conn, query, "dailyActiveDeposits")

      refute called(Sanbase.Clickhouse.DailyActiveDeposits.active_deposits(:_, from, to, :_))
      assert result != nil
    end

    test "can access PRO metrics for more less than 18 months", context do
      {from, to} = from_to(3 * 365 - 1, 10)
      query = daily_active_deposits_query(from, to)
      result = execute_query(context.conn, query, "dailyActiveDeposits")

      assert_called(Sanbase.Clickhouse.DailyActiveDeposits.active_deposits(:_, from, to, :_))
      assert result != nil
    end
  end

  describe "SANBase product, user with PRO plan" do
    setup context do
      insert(:subscription_pro_sanbase, user: context.user)
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

    test "can access RESTRICTED v2 clickhouse metrics for 1 year", context do
      {from, to} = from_to(12 * 30, 0)
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

    test "cannot access BASIC metrics for more than 3 years", context do
      {from, to} = from_to(3 * 365 + 1, 10)
      query = network_growth_query(from, to)
      result = execute_query(context.conn, query, "networkGrowth")

      refute called(Sanbase.Clickhouse.NetworkGrowth.network_growth(:_, from, to, :_))
      assert result != nil
    end

    test "can access BASIC metrics for less than 3 years", context do
      {from, to} = from_to(3 * 365 - 1, 10)
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

    test "cannot access PRO metrics for more than 3 years", context do
      {from, to} = from_to(3 * 365 + 1, 10)
      query = daily_active_deposits_query(from, to)
      result = execute_query(context.conn, query, "dailyActiveDeposits")

      refute called(Sanbase.Clickhouse.DailyActiveDeposits.active_deposits(:_, from, to, :_))
      assert result != nil
    end

    test "can access PRO metrics for more less than 18 months", context do
      {from, to} = from_to(3 * 365 - 1, 10)
      query = daily_active_deposits_query(from, to)
      result = execute_query(context.conn, query, "dailyActiveDeposits")

      assert_called(Sanbase.Clickhouse.DailyActiveDeposits.active_deposits(:_, from, to, :_))
      assert result != nil
    end
  end

  describe "for SANbase when signals limit reached" do
    setup_with_mocks([
      {UserTrigger, [:passthrough], [triggers_count_for: fn _ -> @triggers_limit_count end]}
    ]) do
      :ok
    end

    test "user with FREE plan cannot create new trigger", context do
      assert create_trigger_mutation_with_error(context) ==
               SanbaseAccessChecker.signals_limits_upgrade_message()
    end

    test "user with BASIC plan can create new trigger", context do
      insert(:subscription_pro_sanbase, user: context.user)

      assert create_trigger_mutation(context)["trigger"]["id"] != nil
    end

    test "user with PRO plan can create new trigger", context do
      insert(:subscription_pro_sanbase, user: context.user)

      assert create_trigger_mutation(context)["trigger"]["id"] != nil
    end
  end

  describe "for SANapi when signals limit reached" do
    setup_with_mocks([
      {UserTrigger, [:passthrough], [triggers_count_for: fn _ -> @triggers_limit_count end]}
    ]) do
      :ok
    end

    test "with BASIC plan can create new trigger", context do
      insert(:subscription_essential, user: context.user)

      assert create_trigger_mutation(context)["trigger"]["id"] != nil
    end

    test "with PREMIUM plan can create new trigger", context do
      insert(:subscription_premium, user: context.user)

      assert create_trigger_mutation(context)["trigger"]["id"] != nil
    end
  end

  describe "for FREE plan when signals limits not reached" do
    setup_with_mocks([
      {UserTrigger, [:passthrough], [triggers_count_for: fn _ -> @triggers_limit_count - 1 end]}
    ]) do
      :ok
    end

    test "user can create new trigger", context do
      assert create_trigger_mutation(context)["trigger"]["id"] != nil
    end
  end

  # Private functions

  defp create_trigger_mutation(context) do
    query = create_trigger_mutation()
    execute_mutation(context.conn, query, "createTrigger")
  end

  defp create_trigger_mutation_with_error(context) do
    query = create_trigger_mutation()
    execute_mutation_with_error(context.conn, query)
  end

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

  defp create_trigger_mutation() do
    trigger_settings = %{
      type: "daily_active_addresses",
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
