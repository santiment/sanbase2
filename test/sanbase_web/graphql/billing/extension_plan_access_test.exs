defmodule Sanbase.Billing.ExtensionPlanAccessTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    user = insert(:user)

    conn = setup_jwt_auth(build_conn(), user)

    [user: user, conn: conn]
  end

  setup do
    eth_infr = insert(:infrastructure, %{code: "ETH"})
    exchange_address = insert(:exchange_address, %{infrastructure: eth_infr})
    %{exchange_address: exchange_address}
  end

  test "cannot fetch by free plan", context do
    result = get_all_exchange_wallets(context.conn)

    assert %{
             "data" => %{"allExchangeWallets" => nil},
             "errors" => [
               %{
                 "message" => "unauthorized"
               }
             ]
           } = result
  end

  test "cannot fetch by pro plan", context do
    insert(:subscription_pro, user: context.user)
    result = get_all_exchange_wallets(context.conn)

    assert %{
             "data" => %{"allExchangeWallets" => nil},
             "errors" => [
               %{
                 "message" => "unauthorized"
               }
             ]
           } = result
  end

  test "can fetch by having plan extension", context do
    insert(:subscription_exchange_wallets_extension, user: context.user)

    %{"data" => %{"allExchangeWallets" => [exchange_address]}} =
      get_all_exchange_wallets(context.conn)

    assert exchange_address["address"] == context.exchange_address.address
  end

  defp get_all_exchange_wallets(conn) do
    query = """
    {
      allExchangeWallets {
        address
        infrastructure { code }
        isDex
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end
end
