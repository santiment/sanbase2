defmodule Sanbase.Etherbi.ExchangeWalletsApiTest do
  use SanbaseWeb.ConnCase
  use Phoenix.ConnTest

  alias Sanbase.Model.ExchangeEthAddress
  alias Sanbase.Repo

  import SanbaseWeb.Graphql.TestHelpers

  setup do
    [
      conn: setup_basic_auth(build_conn(), "user", "pass")
    ]
  end

  test "returning an error when there is no bacis auth" do
    query = """
    {
      exchangeWallets{
        address,
        name
      }
    }
    """

    result =
      build_conn()
      |> post("/graphql", query_skeleton(query, "exchangeWallets"))

    assert result.status_code == 403
  end

  test "returning an empty list of wallets if there are none in the DB", context do
    query = """
    {
      exchangeWallets{
        address,
        name
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "exchangeWallets"))

    exchange_wallets = json_response(result, 200)["data"]["exchangeWallets"]

    assert exchange_wallets == []
  end

  test "returning a list of wallets from the DB", context do
    [
      %ExchangeEthAddress{name: "Binance", address: "0x12345"},
      %ExchangeEthAddress{name: "Kraken", address: "0x54321"}
    ]
    |> Repo.insert_all()

    query = """
    {
      exchangeWallets{
        address,
        name
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "exchangeWallets"))

    exchange_wallets = json_response(result, 200)["data"]["exchangeWallets"]

    assert %{name: "Binance", address: "0x12345"} in exchange_wallets
    assert %{name: "Kraken", address: "0x54321"} in exchange_wallets
  end
end
