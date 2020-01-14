defmodule Sanbase.Billing.SanbaseProductAccessTest do
  use SanbaseWeb.ConnCase

  import Mock
  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Signal.UserTrigger
  alias Sanbase.Billing.Plan.SanbaseAccessChecker
  alias Sanbase.Metric

  @triggers_limit_count 10

  setup_with_mocks([
    {Sanbase.Price, [], [timeseries_data: fn _, _, _, _ -> price_resp() end]},
    {Sanbase.Clickhouse.DailyActiveDeposits, [],
     [active_deposits: fn _, _, _, _ -> daily_active_deposits_resp() end]},
    {Sanbase.Clickhouse.NetworkGrowth, [],
     [network_growth: fn _, _, _, _ -> network_growth_resp() end]},
    {Metric, [:passthrough], [timeseries_data: fn _, _, _, _, _, _ -> metric_resp() end]},
    {UserTrigger, [:passthrough], [triggers_count_for: fn _ -> @triggers_limit_count end]}
  ]) do
    :ok
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
      metric = v2_free_metric(context.next_integer.())
      query = metric_query(metric, slug, from, to)
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

    test "cannot access RESTRICTED metrics for over 2 years", context do
      {from, to} = from_to(2 * 365 + 1, 31)
      slug = context.project.slug
      metric = v2_restricted_metric(context.next_integer.())
      query = metric_query(metric, slug, from, to)
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
      contract = context.project.main_contract_address

      assert called(Sanbase.Clickhouse.NetworkGrowth.network_growth(contract, :_, :_, :_))
      refute called(Sanbase.Clickhouse.NetworkGrowth.network_growth(contract, from, to, :_))
      assert result != nil
    end

    test "cannot access RESTRICTED metrics for the past 30 days", context do
      {from, to} = from_to(32, 28)
      slug = context.project.slug
      metric = v2_restricted_metric(context.next_integer.())
      query = metric_query(metric, slug, from, to)
      result = execute_query(context.conn, query, "getMetric")

      refute called(Metric.timeseries_data(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "cannot access RESTRICTED metrics for the past 30 days - both params outside allowed",
         context do
      {from, to} = from_to(20, 10)
      slug = context.project.slug
      metric = v2_restricted_metric(context.next_integer.())
      query = metric_query(metric, slug, from, to)
      result = execute_query_with_error(context.conn, query, "getMetric")

      refute called(Metric.timeseries_data(metric, :_, :_, :_, :_, :_))
      assert result != nil
    end

    test "cannot access RESTRICTED queries for the past 30 days", context do
      {from, to} = from_to(31, 29)
      slug = context.project.slug
      query = network_growth_query(slug, from, to)
      result = execute_query(context.conn, query, "networkGrowth")
      contract = context.project.main_contract_address

      refute called(Sanbase.Clickhouse.NetworkGrowth.network_growth(contract, from, to, :_))
      assert result != nil
    end

    test "cannot access RESTRICTED queries for the past 30 days - both params outside allowed",
         context do
      {from, to} = from_to(20, 10)
      slug = context.project.slug
      query = network_growth_query(slug, from, to)
      result = execute_query_with_error(context.conn, query, "networkGrowth")
      contract = context.project.main_contract_address

      refute called(Sanbase.Clickhouse.NetworkGrowth.network_growth(contract, from, to, :_))
      assert result != nil
    end

    test "can access RESTRICTED queries within 2 years and 30 day ago interval", context do
      {from, to} = from_to(2 * 365 - 1, 31)
      slug = context.project.slug
      query = network_growth_query(slug, from, to)
      result = execute_query(context.conn, query, "networkGrowth")
      contract = context.project.main_contract_address

      assert_called(Sanbase.Clickhouse.NetworkGrowth.network_growth(contract, from, to, :_))
      assert result != nil
    end

    test "can access RESTRICTED metrics within 2 years and 30 day ago interval", context do
      {from, to} = from_to(2 * 365 - 1, 31)
      slug = context.project.slug
      metric = v2_restricted_metric(context.next_integer.())
      query = metric_query(metric, slug, from, to)
      result = execute_query(context.conn, query, "getMetric")

      assert_called(Metric.timeseries_data(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "fallbacks to API pro subscription if exists", context do
      insert(:subscription_pro, user: context.user)

      from = Timex.shift(Timex.now(), days: -(5 * 365 - 1))
      to = Timex.now()
      slug = context.project.slug
      query = daily_active_deposits_query(slug, from, to)
      result = execute_query(context.conn, query, "dailyActiveDeposits")
      contract = context.project.main_contract_address

      assert_called(
        Sanbase.Clickhouse.DailyActiveDeposits.active_deposits(contract, from, to, :_)
      )

      assert result != nil
    end

    test "fallbacks to PREMIUM subscription if exists", context do
      insert(:subscription_premium, user: context.user)
      {from, to} = from_to(18 * 30 + 1, 0)
      slug = context.project.slug
      query = daily_active_deposits_query(slug, from, to)
      result = execute_query(context.conn, query, "dailyActiveDeposits")
      contract = context.project.main_contract_address

      assert_called(
        Sanbase.Clickhouse.DailyActiveDeposits.active_deposits(contract, from, to, :_)
      )

      assert result != nil
    end
  end

  describe "SANBase product, user with PRO plan" do
    setup context do
      insert(:subscription_pro_sanbase, user: context.user)
      :ok
    end

    test "can access FREE metrics for all time", context do
      {from, to} = from_to(2500, 0)
      slug = context.project.slug
      metric = v2_free_metric(context.next_integer.())
      query = metric_query(metric, slug, from, to)
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

    test "can access RESTRICTED v2 clickhouse metrics for 1 year", context do
      {from, to} = from_to(12 * 30, 0)
      slug = context.project.slug
      metric = v2_restricted_metric(context.next_integer.())
      query = metric_query(metric, slug, from, to)
      result = execute_query(context.conn, query, "getMetric")
      assert_called(Metric.timeseries_data(metric, :_, from, to, :_, :_))
      assert result != nil
    end

    test "cannot access RESTRICTED metrics for more than 5 years", context do
      {from, to} = from_to(5 * 365 + 1, 10)
      slug = context.project.slug
      query = network_growth_query(slug, from, to)
      result = execute_query(context.conn, query, "networkGrowth")
      contract = context.project.main_contract_address

      refute called(Sanbase.Clickhouse.NetworkGrowth.network_growth(contract, from, to, :_))
      assert result != nil
    end

    test "can access RESTRICTED metrics for less than 5 years", context do
      {from, to} = from_to(5 * 365 - 1, 10)
      slug = context.project.slug
      query = network_growth_query(slug, from, to)
      result = execute_query(context.conn, query, "networkGrowth")
      contract = context.project.main_contract_address

      assert_called(Sanbase.Clickhouse.NetworkGrowth.network_growth(contract, from, to, :_))
      assert result != nil
    end

    test "can access RESTRICTED metrics realtime", context do
      {from, to} = from_to(10, 0)
      slug = context.project.slug
      query = network_growth_query(slug, from, to)
      result = execute_query(context.conn, query, "networkGrowth")
      contract = context.project.main_contract_address

      assert_called(Sanbase.Clickhouse.NetworkGrowth.network_growth(contract, from, to, :_))
      assert result != nil
    end

    test "cannot access RESTRICTED queries for more than 5 years", context do
      {from, to} = from_to(5 * 365 + 1, 10)
      slug = context.project.slug
      query = daily_active_deposits_query(slug, from, to)
      result = execute_query(context.conn, query, "dailyActiveDeposits")
      contract = context.project.main_contract_address

      refute called(
               Sanbase.Clickhouse.DailyActiveDeposits.active_deposits(contract, from, to, :_)
             )

      assert result != nil
    end

    test "can access RESTRICTED queries for less than 5 years", context do
      {from, to} = from_to(5 * 365 - 1, 10)
      slug = context.project.slug
      query = daily_active_deposits_query(slug, from, to)
      result = execute_query(context.conn, query, "dailyActiveDeposits")
      contract = context.project.main_contract_address

      assert_called(
        Sanbase.Clickhouse.DailyActiveDeposits.active_deposits(contract, from, to, :_)
      )

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

  defp v2_free_metric(position), do: Metric.free_metrics() |> Stream.cycle() |> Enum.at(position)

  defp v2_restricted_metric(position),
    do: Metric.restricted_metrics() |> Stream.cycle() |> Enum.at(position)

  defp from_to(from_days_shift, to_days_shift) do
    from = Timex.shift(Timex.now(), days: -from_days_shift)
    to = Timex.shift(Timex.now(), days: -to_days_shift)
    {from, to}
  end

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

  defp daily_active_deposits_resp() do
    {:ok,
     [
       %{active_deposits: 0.1, datetime: ~U[2019-01-01 00:00:00Z]},
       %{active_deposits: 0.2, datetime: ~U[2019-01-02 00:00:00Z]}
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

  defp network_growth_resp() do
    {:ok,
     [
       %{new_addresses: 10, datetime: ~U[2019-01-01 00:00:00Z]},
       %{new_addresses: 20, datetime: ~U[2019-01-02 00:00:00Z]}
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
