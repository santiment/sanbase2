defmodule Sanbase.Etherbi.ExchangeWalletsApiTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers

  setup do
    [
      conn: setup_basic_auth(build_conn(), "user", "pass")
    ]
  end

  test "returning an error when there is no basic auth", context do
    query = """
    {
      exchangeWallets(slug: "ethereum"){
        address
        name
        isDex
      }
    }
    """

    err_msg = execute_query_with_error(context.not_logged_conn, query, "exchangeWallets")
    assert err_msg == "unauthorized"
  end

  test "returning a list of wallets from the DB", context do
    Sanbase.Mock.prepare_mock2(
      &Sanbase.Clickhouse.ExchangeAddress.exchange_addresses/1,
      {:ok,
       [
         %{address: "0x12345", name: "Binance", is_dex: false},
         %{address: "0x54321", name: "Kraken", is_dex: false}
       ]}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      wallets =
        get_exchange_wallets(context.conn, "ethereum")
        |> get_in(["data", "exchangeWallets"])

      assert %{"name" => "Binance", "address" => "0x12345", "isDex" => false} in wallets
      assert %{"name" => "Kraken", "address" => "0x54321", "isDex" => false} in wallets
    end)
  end

  test "returning a list of all wallets from the DB", context do
    Sanbase.Mock.prepare_mock2(
      &Sanbase.Clickhouse.ExchangeAddress.exchange_addresses/1,
      {:ok,
       [
         %{address: "0x12345", name: "Binance", is_dex: true},
         %{address: "0x54321", name: "Kraken", is_dex: false}
       ]}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      wallets =
        get_exchange_wallets(context.conn, "ethereum")
        |> get_in(["data", "exchangeWallets"])

      assert %{"name" => "Binance", "address" => "0x12345", "isDex" => true} in wallets
      assert %{"name" => "Kraken", "address" => "0x54321", "isDex" => false} in wallets
    end)
  end

  defp get_exchange_wallets(conn, slug) do
    query = """
    {
      exchangeWallets(slug: "#{slug}"){
        address
        name
        isDex
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query, "exchangeWallets"))
    |> json_response(200)
  end
end
