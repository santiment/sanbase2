defmodule SanbaseWeb.Graphql.SanbaseNftApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.SmartContracts.SanbaseNft
  alias Sanbase.Accounts.EthAccount

  setup do
    user =
      insert(:user, eth_accounts: [%EthAccount{address: "0x123"}, %EthAccount{address: "0x234"}])

    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn, user: user}
  end

  test "when there are nfts - return true", context do
    mock_fun =
      [
        fn -> [] end,
        fn -> [1, 3, 5] end
      ]
      |> Sanbase.Mock.wrap_consecutives(arity: 1)

    Sanbase.Mock.prepare_mock(
      Sanbase.SmartContracts.SanbaseNft,
      :nft_subscriptions_data,
      mock_fun
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      result = sanbase_nft(context.conn)
      assert result["sanbaseNft"]["hasValidNft"]
      assert result["sanbaseNft"]["nftCount"] == 3
      assert %{"address" => "0x234", "tokenIds" => [1, 3, 5]} in result["sanbaseNft"]["nftData"]
    end)
  end

  test "when there are no nfts - return false", context do
    mock_fun =
      [
        fn -> [] end
      ]
      |> Sanbase.Mock.wrap_consecutives(arity: 1)

    Sanbase.Mock.prepare_mock(
      Sanbase.SmartContracts.SanbaseNft,
      :nft_subscriptions_data,
      mock_fun
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      result = sanbase_nft(context.conn)
      refute result["sanbaseNft"]["hasValidNft"]
      assert result["sanbaseNft"]["nftCount"] == 0
    end)
  end

  def sanbase_nft(conn) do
    query = """
    {
      currentUser {
        sanbaseNft {
          hasValidNft
          nftCount
          nftData {
            address
            tokenIds
          }
        }
      }
    }
    """

    execute_query(conn, query, "currentUser")
  end
end
