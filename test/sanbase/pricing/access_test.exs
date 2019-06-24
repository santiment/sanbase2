defmodule Sanbase.Pricing.AccessTest do
  use SanbaseWeb.ConnCase

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers
  import Mock
  import Sanbase.DateTimeUtils, only: [from_iso8601!: 1]

  alias Sanbase.Auth.Apikey
  alias Sanbase.Pricing.TestSeed

  setup_with_mocks([
    {Sanbase.Clickhouse.MVRV, [], [mvrv_ratio: fn _, _, _, _ -> mvrv_resp() end]},
    {Sanbase.Clickhouse.NetworkGrowth, [],
     [network_growth: fn _, _, _, _ -> network_growth_resp() end]}
  ]) do
    free_user = insert(:user)
    user = insert(:staked_user)

    TestSeed.seed_products_and_plans()

    {:ok, apikey} = Apikey.generate_apikey(user)
    conn_apikey = setup_apikey_auth(build_conn(), apikey)

    {:ok, apikey_free} = Apikey.generate_apikey(free_user)
    conn_apikey_free = setup_apikey_auth(build_conn(), apikey_free)

    {:ok, user: user, conn_apikey: conn_apikey, conn_apikey_free: conn_apikey_free}
  end

  describe "Free user, staked" do
    test "can access STANDART metrics for all time", context do
      from = Timex.shift(Timex.now(), days: -(100 + 1))
      to = Timex.now()
      query = network_growth_query(from, to)
      result = execute_query(context.conn_apikey, query, "networkGrowth")
      assert_called(Sanbase.Clickhouse.NetworkGrowth.network_growth(:_, from, to, :_))
      assert result != nil
    end

    test "can access ADVANCED metrics for all time", context do
      from = Timex.shift(Timex.now(), days: -(100 + 1))
      to = Timex.now()
      query = mvrv_query(from, to)
      result = execute_query(context.conn_apikey, query, "mvrvRatio")

      assert_called(Sanbase.Clickhouse.MVRV.mvrv_ratio(:_, from, to, :_))
      assert result != nil
    end
  end

  describe "Free user, not staked" do
    test "can access STANDART metrics for 3 months", context do
      from = Timex.shift(Timex.now(), days: -(100 + 1))
      to = Timex.now()
      query = network_growth_query(from, to)
      result = execute_query(context.conn_apikey_free, query, "networkGrowth")

      refute called(Sanbase.Clickhouse.NetworkGrowth.network_growth(:_, from, to, :_))
      assert result != nil
    end

    test "can access ADVANCED metrics for 3 months", context do
      from = Timex.shift(Timex.now(), days: -(100 + 1))
      to = Timex.now()
      query = mvrv_query(from, to)
      result = execute_query(context.conn_apikey_free, query, "mvrvRatio")

      refute called(Sanbase.Clickhouse.MVRV.mvrv_ratio(:_, from, to, :_))
      assert result != nil
    end
  end

  describe "user with ESSENTIAL (STANDART metrics) plan" do
    test "can access STANDART metrics for 180 days", context do
      insert(:subscription_essential, user: context.user)

      from = Timex.shift(Timex.now(), days: -(100 + 1))
      to = Timex.now()
      query = network_growth_query(from, to)
      result = execute_query(context.conn_apikey_free, query, "networkGrowth")

      refute called(Sanbase.Clickhouse.NetworkGrowth.network_growth(:_, from, to, :_))
      assert result != nil
    end

    test "can't access ADVANCED metrics", context do
      insert(:subscription_essential, user: context.user)

      from = Timex.shift(Timex.now(), days: -(100 + 1))
      to = Timex.now()
      query = mvrv_query(from, to)

      error_msg = execute_query_with_error(context.conn_apikey, query, "mvrvRatio")

      refute called(Sanbase.Clickhouse.MVRV.mvrv_ratio(:_, from, to, :_))

      assert error_msg == """
             Requested metric mvrv_ratio is not provided by the current subscription plan ESSENTIAL.
             Please upgrade to PRO or PREMIUM or CUSTOM to get access to mvrv_ratio
             """
    end
  end

  describe "user with PRO (ADVANCED metrics) plan" do
    test "can access STANDART metrics for #{18 * 30} days", context do
      insert(:subscription_pro, user: context.user)

      from = Timex.shift(Timex.now(), days: -(18 * 30 + 1))
      to = Timex.now()
      query = network_growth_query(from, to)
      result = execute_query(context.conn_apikey_free, query, "networkGrowth")

      refute called(Sanbase.Clickhouse.NetworkGrowth.network_growth(:_, from, to, :_))
      assert result != nil
    end

    test "can access ADVANCED metrics for #{18 * 30} days", context do
      insert(:subscription_pro, user: context.user)

      from = Timex.shift(Timex.now(), days: -(18 * 30 + 1))
      to = Timex.now()
      query = mvrv_query(from, to)
      result = execute_query(context.conn_apikey_free, query, "mvrvRatio")

      refute called(Sanbase.Clickhouse.MVRV.mvrv_ratio(:_, from, to, :_))
      assert result != nil
    end
  end

  defp mvrv_query(from, to) do
    """
      {
        mvrvRatio(slug: "ethereum", from: "#{from}", to: "#{to}", interval: "1d"){
          datetime,
          ratio
        }
      }
    """
  end

  defp network_growth_query(from, to) do
    """
      {
        networkGrowth(slug: "ethereum", from: "#{from}", to: "#{to}", interval: "1d"){
          datetime,
          newAddresses
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

  defp network_growth_resp() do
    {:ok,
     [
       %{new_addresses: 10, datetime: from_iso8601!("2019-01-01T00:00:00Z")},
       %{new_addresses: 20, datetime: from_iso8601!("2019-01-02T00:00:00Z")}
     ]}
  end
end
