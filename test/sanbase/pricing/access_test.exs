defmodule Sanbase.Billing.AccessTest do
  use SanbaseWeb.ConnCase

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers
  import Mock
  import Sanbase.DateTimeUtils, only: [from_iso8601!: 1]

  alias Sanbase.Auth.Apikey
  alias Sanbase.Billing.TestSeed

  setup_with_mocks([
    {Sanbase.Prices.Store, [], [fetch_prices_with_resolution: fn _, _, _, _ -> price_resp() end]},
    {Sanbase.Clickhouse.MVRV, [], [mvrv_ratio: fn _, _, _, _ -> mvrv_resp() end]},
    {Sanbase.Clickhouse.NetworkGrowth, [],
     [network_growth: fn _, _, _, _ -> network_growth_resp() end]}
  ]) do
    user = insert(:user)
    staking_user = insert(:staked_user)
    project = insert(:random_project)

    TestSeed.seed_products_and_plans()

    {:ok, apikey} = Apikey.generate_apikey(staking_user)
    conn_staking = setup_apikey_auth(build_conn(), apikey)

    {:ok, apikey} = Apikey.generate_apikey(user)
    conn = setup_apikey_auth(build_conn(), apikey)

    [user: user, conn_staking: conn_staking, conn: conn, project: project]
  end

  # TODO: Remove once staking is disabled
  describe "No subscription, staking tokens user" do
    test "can access FREE metrics for all time", context do
      from = Timex.shift(Timex.now(), days: -900)
      to = Timex.now()
      query = history_price_query(context.project, from, to)
      result = execute_query(context.conn_staking, query, "historyPrice")

      assert_called(Sanbase.Prices.Store.fetch_prices_with_resolution(:_, from, to, :_))
      assert result != nil
    end

    test "can access BASIC metrics for all time", context do
      from = Timex.shift(Timex.now(), days: -900)
      to = Timex.now()
      query = network_growth_query(from, to)
      result = execute_query(context.conn_staking, query, "networkGrowth")
      assert_called(Sanbase.Clickhouse.NetworkGrowth.network_growth(:_, from, to, :_))
      assert result != nil
    end

    test "can access PRO metrics for all time", context do
      from = Timex.shift(Timex.now(), days: -900)
      to = Timex.now()
      query = mvrv_query(from, to)

      result = execute_query(context.conn_staking, query, "mvrvRatio")

      assert_called(Sanbase.Clickhouse.MVRV.mvrv_ratio(:_, from, to, :_))
      assert result != nil
    end
  end

  describe "No subscription, not staking user" do
    test "can access FREE metrics for all time", context do
      from = Timex.shift(Timex.now(), days: -900)
      to = Timex.now()
      query = history_price_query(context.project, from, to)
      result = execute_query(context.conn, query, "historyPrice")

      assert_called(Sanbase.Prices.Store.fetch_prices_with_resolution(:_, from, to, :_))
      assert result != nil
    end

    test "cannot access BASIC metrics for over 3 months", context do
      from = Timex.shift(Timex.now(), days: -91)
      to = Timex.shift(Timex.now(), days: -10)
      query = network_growth_query(from, to)
      result = execute_query(context.conn, query, "networkGrowth")

      refute called(Sanbase.Clickhouse.NetworkGrowth.network_growth(:_, from, to, :_))
      assert result != nil
    end

    test "cannot access BASIC metrics realtime", context do
      from = Timex.shift(Timex.now(), days: -10)
      to = Timex.now()
      query = network_growth_query(from, to)
      result = execute_query(context.conn, query, "networkGrowth")

      refute called(Sanbase.Clickhouse.NetworkGrowth.network_growth(:_, from, to, :_))
      assert result != nil
    end

    test "can access BASIC metrics within 90 days and 1 day interval", context do
      from = Timex.shift(Timex.now(), days: -89)
      to = Timex.shift(Timex.now(), days: -2)
      query = network_growth_query(from, to)
      result = execute_query(context.conn, query, "networkGrowth")

      assert_called(Sanbase.Clickhouse.NetworkGrowth.network_growth(:_, from, to, :_))
      assert result != nil
    end

    test "cannot access PRO metrics for over 3 months", context do
      from = Timex.shift(Timex.now(), days: -91)
      to = Timex.shift(Timex.now(), days: -10)
      query = mvrv_query(from, to)
      result = execute_query(context.conn, query, "mvrvRatio")

      refute called(Sanbase.Clickhouse.MVRV.mvrv_ratio(:_, from, to, :_))
      assert result != nil
    end

    test "cannot access PRO metrics realtime", context do
      from = Timex.shift(Timex.now(), days: -10)
      to = Timex.now()
      query = mvrv_query(from, to)
      result = execute_query(context.conn, query, "mvrvRatio")

      refute called(Sanbase.Clickhouse.MVRV.mvrv_ratio(:_, from, to, :_))
      assert result != nil
    end

    test "can access PRO withing 90 days and 1 day interval", context do
      from = Timex.shift(Timex.now(), days: -89)
      to = Timex.shift(Timex.now(), days: -2)
      query = mvrv_query(from, to)
      result = execute_query(context.conn, query, "mvrvRatio")

      assert_called(Sanbase.Clickhouse.MVRV.mvrv_ratio(:_, from, to, :_))
      assert result != nil
    end
  end

  describe "user with BASIC plan" do
    test "can access FREE metrics for all time", context do
      insert(:subscription_essential, user: context.user)

      from = Timex.shift(Timex.now(), days: -900)
      to = Timex.now()
      query = history_price_query(context.project, from, to)
      result = execute_query(context.conn, query, "historyPrice")

      assert_called(Sanbase.Prices.Store.fetch_prices_with_resolution(:_, from, to, :_))
      assert result != nil
    end

    test "cannot access BASIC metrics for more than 180 days", context do
      insert(:subscription_essential, user: context.user)

      from = Timex.shift(Timex.now(), days: -181)
      to = Timex.shift(Timex.now(), days: -3)
      query = network_growth_query(from, to)
      result = execute_query(context.conn, query, "networkGrowth")

      refute called(Sanbase.Clickhouse.NetworkGrowth.network_growth(:_, from, to, :_))
      assert result != nil
    end

    test "can access BASIC metrics for less than 180 days", context do
      insert(:subscription_essential, user: context.user)

      from = Timex.shift(Timex.now(), days: -179)
      to = Timex.shift(Timex.now(), days: -3)
      query = network_growth_query(from, to)
      result = execute_query(context.conn, query, "networkGrowth")

      assert_called(Sanbase.Clickhouse.NetworkGrowth.network_growth(:_, from, to, :_))
      assert result != nil
    end

    test "can access BASIC metrics realtime", context do
      insert(:subscription_essential, user: context.user)

      from = Timex.shift(Timex.now(), days: -10)
      to = Timex.now()
      query = network_growth_query(from, to)
      result = execute_query(context.conn, query, "networkGrowth")

      assert_called(Sanbase.Clickhouse.NetworkGrowth.network_growth(:_, from, to, :_))
      assert result != nil
    end

    test "cannot access PRO metrics", context do
      insert(:subscription_essential, user: context.user)

      from = Timex.shift(Timex.now(), days: -91)
      to = Timex.now()
      query = mvrv_query(from, to)

      error_msg = execute_query_with_error(context.conn, query, "mvrvRatio")

      refute called(Sanbase.Clickhouse.MVRV.mvrv_ratio(:_, from, to, :_))

      assert error_msg =~ """
             Requested metric mvrv_ratio is not provided by the current subscription plan ESSENTIAL.
             Please upgrade to Pro or higher to get access to mvrv_ratio
             """
    end
  end

  describe "user with PRO plan" do
    test "can access FREE metrics for all time", context do
      insert(:subscription_pro, user: context.user)

      from = Timex.shift(Timex.now(), days: -900)
      to = Timex.now()
      query = history_price_query(context.project, from, to)
      result = execute_query(context.conn, query, "historyPrice")

      assert_called(Sanbase.Prices.Store.fetch_prices_with_resolution(:_, from, to, :_))
      assert result != nil
    end

    test "cannot access BASIC metrics for more than 18 months", context do
      insert(:subscription_pro, user: context.user)

      from = Timex.shift(Timex.now(), days: -(18 * 30 + 1))
      to = Timex.now()
      query = network_growth_query(from, to)
      result = execute_query(context.conn, query, "networkGrowth")

      refute called(Sanbase.Clickhouse.NetworkGrowth.network_growth(:_, from, to, :_))
      assert result != nil
    end

    test "can access BASIC metrics for less than 18 months", context do
      insert(:subscription_pro, user: context.user)

      from = Timex.shift(Timex.now(), days: -(18 * 30 - 1))
      to = Timex.now()
      query = network_growth_query(from, to)
      result = execute_query(context.conn, query, "networkGrowth")

      assert_called(Sanbase.Clickhouse.NetworkGrowth.network_growth(:_, from, to, :_))
      assert result != nil
    end

    test "cannot access PRO metrics for more than 18 months", context do
      insert(:subscription_pro, user: context.user)

      from = Timex.shift(Timex.now(), days: -(18 * 30 + 1))
      to = Timex.now()
      query = mvrv_query(from, to)
      result = execute_query(context.conn, query, "mvrvRatio")

      refute called(Sanbase.Clickhouse.MVRV.mvrv_ratio(:_, from, to, :_))
      assert result != nil
    end

    test "can access PRO metrics for more less than 18 months", context do
      insert(:subscription_pro, user: context.user)

      from = Timex.shift(Timex.now(), days: -(18 * 30 - 1))
      to = Timex.now()
      query = mvrv_query(from, to)
      result = execute_query(context.conn, query, "mvrvRatio")

      assert_called(Sanbase.Clickhouse.MVRV.mvrv_ratio(:_, from, to, :_))
      assert result != nil
    end
  end

  describe "user with PREMIUM plan" do
    test "can access FREE metrics for all time", context do
      insert(:subscription_premium, user: context.user)

      from = Timex.shift(Timex.now(), days: -900)
      to = Timex.now()
      query = history_price_query(context.project, from, to)
      result = execute_query(context.conn, query, "historyPrice")

      assert_called(Sanbase.Prices.Store.fetch_prices_with_resolution(:_, from, to, :_))
      assert result != nil
    end

    test "can access BASIC metrics for all time", context do
      insert(:subscription_premium, user: context.user)

      from = Timex.shift(Timex.now(), days: -900)
      to = Timex.now()
      query = network_growth_query(from, to)
      result = execute_query(context.conn, query, "networkGrowth")

      assert_called(Sanbase.Clickhouse.NetworkGrowth.network_growth(:_, from, to, :_))
      assert result != nil
    end

    test "can access PRO metrics for all time", context do
      insert(:subscription_premium, user: context.user)

      from = Timex.shift(Timex.now(), days: -900)
      to = Timex.now()
      query = mvrv_query(from, to)
      result = execute_query(context.conn, query, "mvrvRatio")

      assert_called(Sanbase.Clickhouse.MVRV.mvrv_ratio(:_, from, to, :_))
      assert result != nil
    end
  end

  defp mvrv_query(from, to) do
    """
      {
        mvrvRatio(slug: "ethereum", from: "#{from}", to: "#{to}", interval: "1d"){
          datetime
          ratio
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
        historyPrice(slug: "#{project.coinmarketcap_id}", from: "#{from}", to: "#{to}", interval: "1d"){
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
