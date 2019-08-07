defmodule Sanbase.Billing.SanbaseProductAccessTest do
  use SanbaseWeb.ConnCase

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers
  import Mock
  import Sanbase.DateTimeUtils, only: [from_iso8601!: 1]

  setup_with_mocks([
    {Sanbase.Prices.Store, [], [fetch_prices_with_resolution: fn _, _, _, _ -> price_resp() end]},
    {Sanbase.Clickhouse.MVRV, [], [mvrv_ratio: fn _, _, _, _ -> mvrv_resp() end]},
    {Sanbase.Clickhouse.DailyActiveDeposits, [],
     [active_deposits: fn _, _, _, _ -> daily_active_deposits_resp() end]},
    {Sanbase.Clickhouse.NetworkGrowth, [],
     [network_growth: fn _, _, _, _ -> network_growth_resp() end]}
  ]) do
    user = insert(:user)
    project = insert(:random_project)

    conn = setup_jwt_auth(build_conn(), user)

    [user: user, conn: conn, project: project]
  end

  describe "SANBase product, No subscription" do
    test "can access FREE metrics for all time", context do
      from = Timex.shift(Timex.now(), days: -1500)
      to = Timex.now()
      query = history_price_query(context.project, from, to)
      result = execute_query(context.conn, query, "historyPrice")

      assert_called(Sanbase.Prices.Store.fetch_prices_with_resolution(:_, from, to, :_))
      assert result != nil
    end

    test "cannot access BASIC metrics for over 2 years", context do
      from = Timex.shift(Timex.now(), days: -(2 * 365 + 1))
      to = Timex.shift(Timex.now(), days: -31)
      query = network_growth_query(from, to)
      result = execute_query(context.conn, query, "networkGrowth")

      refute called(Sanbase.Clickhouse.NetworkGrowth.network_growth(:_, from, to, :_))
      assert result != nil
    end

    test "cannot access BASIC metrics more than 30 days", context do
      from = Timex.shift(Timex.now(), days: -31)
      to = Timex.shift(Timex.now(), days: -29)
      query = network_growth_query(from, to)
      result = execute_query(context.conn, query, "networkGrowth")

      refute called(Sanbase.Clickhouse.NetworkGrowth.network_growth(:_, from, to, :_))
      assert result != nil
    end

    test "can access BASIC metrics within 2 years and 30 day ago interval", context do
      from = Timex.shift(Timex.now(), days: -(2 * 365 - 1))
      to = Timex.shift(Timex.now(), days: -31)
      query = network_growth_query(from, to)
      result = execute_query(context.conn, query, "networkGrowth")

      assert_called(Sanbase.Clickhouse.NetworkGrowth.network_growth(:_, from, to, :_))
      assert result != nil
    end

    test "can access PRO metrics at all", context do
      from = Timex.shift(Timex.now(), days: -34)
      to = Timex.shift(Timex.now(), days: -31)
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

      from = Timex.shift(Timex.now(), days: -(18 * 30 + 1))
      to = Timex.now()
      query = daily_active_deposits_query(from, to)
      result = execute_query(context.conn, query, "dailyActiveDeposits")

      assert_called(Sanbase.Clickhouse.DailyActiveDeposits.active_deposits(:_, from, to, :_))
      assert result != nil
    end
  end

  describe "SANBase product, user with BASIC plan" do
    test "can access FREE metrics for all time", context do
      insert(:subscription_basic_sanbase, user: context.user)

      from = Timex.shift(Timex.now(), days: -1500)
      to = Timex.now()
      query = history_price_query(context.project, from, to)
      result = execute_query(context.conn, query, "historyPrice")

      assert_called(Sanbase.Prices.Store.fetch_prices_with_resolution(:_, from, to, :_))
      assert result != nil
    end

    test "cannot access BASIC metrics for more than 2 years", context do
      insert(:subscription_basic_sanbase, user: context.user)

      from = Timex.shift(Timex.now(), days: -(2 * 365 + 1))
      to = Timex.shift(Timex.now(), days: -10)
      query = network_growth_query(from, to)
      result = execute_query(context.conn, query, "networkGrowth")

      refute called(Sanbase.Clickhouse.NetworkGrowth.network_growth(:_, from, to, :_))
      assert result != nil
    end

    test "can access BASIC metrics for less than 2 years", context do
      insert(:subscription_basic_sanbase, user: context.user)

      from = Timex.shift(Timex.now(), days: -(2 * 365 - 1))
      to = Timex.shift(Timex.now(), days: -8)
      query = network_growth_query(from, to)
      result = execute_query(context.conn, query, "networkGrowth")

      assert_called(Sanbase.Clickhouse.NetworkGrowth.network_growth(:_, from, to, :_))
      assert result != nil
    end

    test "can access BASIC metrics for more than 7 days ago", context do
      insert(:subscription_basic_sanbase, user: context.user)

      from = Timex.shift(Timex.now(), days: -10)
      to = Timex.shift(Timex.now(), days: -8)
      query = network_growth_query(from, to)
      result = execute_query(context.conn, query, "networkGrowth")

      assert_called(Sanbase.Clickhouse.NetworkGrowth.network_growth(:_, from, to, :_))
      assert result != nil
    end

    test "can access PRO metrics", context do
      insert(:subscription_basic_sanbase, user: context.user)

      from = Timex.shift(Timex.now(), days: -10)
      to = Timex.shift(Timex.now(), days: -8)
      query = daily_active_deposits_query(from, to)
      result = execute_query(context.conn, query, "dailyActiveDeposits")

      assert_called(Sanbase.Clickhouse.DailyActiveDeposits.active_deposits(:_, from, to, :_))
      assert result != nil
    end
  end

  describe "SANBase product, user with PRO plan" do
    test "can access FREE metrics for all time", context do
      insert(:subscription_pro_sanbase, user: context.user)

      from = Timex.shift(Timex.now(), days: -1500)
      to = Timex.now()
      query = history_price_query(context.project, from, to)
      result = execute_query(context.conn, query, "historyPrice")

      assert_called(Sanbase.Prices.Store.fetch_prices_with_resolution(:_, from, to, :_))
      assert result != nil
    end

    test "cannot access BASIC metrics for more than 3 years", context do
      insert(:subscription_pro_sanbase, user: context.user)

      from = Timex.shift(Timex.now(), days: -(3 * 365 + 1))
      to = Timex.now()
      query = network_growth_query(from, to)
      result = execute_query(context.conn, query, "networkGrowth")

      refute called(Sanbase.Clickhouse.NetworkGrowth.network_growth(:_, from, to, :_))
      assert result != nil
    end

    test "can access BASIC metrics for less than 3 years", context do
      insert(:subscription_pro_sanbase, user: context.user)

      from = Timex.shift(Timex.now(), days: -(3 * 365 - 1))
      to = Timex.now()
      query = network_growth_query(from, to)
      result = execute_query(context.conn, query, "networkGrowth")

      assert_called(Sanbase.Clickhouse.NetworkGrowth.network_growth(:_, from, to, :_))
      assert result != nil
    end

    test "cannot access PRO metrics for more than 3 years", context do
      insert(:subscription_pro_sanbase, user: context.user)

      from = Timex.shift(Timex.now(), days: -(3 * 365 + 1))
      to = Timex.now()
      query = daily_active_deposits_query(from, to)
      result = execute_query(context.conn, query, "dailyActiveDeposits")

      refute called(Sanbase.Clickhouse.DailyActiveDeposits.active_deposits(:_, from, to, :_))
      assert result != nil
    end

    test "can access PRO metrics for more less than 18 months", context do
      insert(:subscription_pro_sanbase, user: context.user)

      from = Timex.shift(Timex.now(), days: -(3 * 365 - 1))
      to = Timex.now()
      query = daily_active_deposits_query(from, to)
      result = execute_query(context.conn, query, "dailyActiveDeposits")

      assert_called(Sanbase.Clickhouse.DailyActiveDeposits.active_deposits(:_, from, to, :_))
      assert result != nil
    end
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
        historyPrice(slug: "#{project.coinmarketcap_id}", from: "#{from}", to: "#{to}", interval: "30d"){
          datetime
          priceUsd
        }
      }
    """
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
       [from_iso8601!("2019-01-01T00:00:00Z"), 10, 0.1, 10000, 500],
       [from_iso8601!("2019-01-01T00:00:00Z"), 20, 0.2, 20000, 1500]
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
