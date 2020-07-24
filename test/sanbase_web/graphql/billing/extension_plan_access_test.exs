defmodule Sanbase.Billing.ExtensionPlanAccessTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    user = insert(:user)

    conn = setup_jwt_auth(build_conn(), user)

    [user: user, conn: conn]
  end

  test "cannot fetch by free plan", context do
    result = exchange_wallets(context.conn)

    assert %{
             "data" => %{"exchangeWallets" => nil},
             "errors" => [
               %{
                 "message" => "unauthorized"
               }
             ]
           } = result
  end

  test "cannot fetch by pro plan", context do
    insert(:subscription_pro, user: context.user)
    result = exchange_wallets(context.conn)

    assert %{
             "data" => %{"exchangeWallets" => nil},
             "errors" => [
               %{
                 "message" => "unauthorized"
               }
             ]
           } = result
  end

  test "can fetch by having plan extension", context do
    insert(:subscription_exchange_wallets_extension, user: context.user)

    address = "0x127319871293912"

    Sanbase.Mock.prepare_mock2(
      &Sanbase.Clickhouse.ExchangeAddress.exchange_addresses/1,
      {:ok, [%{name: "Binance", address: address, is_dex: false}]}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      %{"data" => %{"exchangeWallets" => [exchange_address]}} = exchange_wallets(context.conn)

      assert exchange_address["address"] == address
    end)
  end

  defp exchange_wallets(conn) do
    query = """
    {
      exchangeWallets(slug: "ethereum") {
        address
        isDex
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end
end
