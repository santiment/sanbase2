defmodule SanbaseWeb.Graphql.SanbaseNFTApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.SmartContracts.SanbaseNFT
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
        fn -> %{valid: [], non_valid: []} end,
        fn -> %{valid: [1, 3, 5], non_valid: [2]} end
      ]
      |> Sanbase.Mock.wrap_consecutives(arity: 1)

    Sanbase.Mock.prepare_mock(SanbaseNFT, :nft_subscriptions_data, mock_fun)
    |> Sanbase.Mock.run_with_mocks(fn ->
      result = sanbase_nft(context.conn)
      assert result["sanbaseNft"]["hasValidNft"]
      assert result["sanbaseNft"]["hasNonValidNft"]
      assert result["sanbaseNft"]["nftCount"] == 3
      assert result["sanbaseNft"]["nonValidNftCount"] == 1

      assert %{"address" => "0x234", "tokenIds" => [1, 3, 5], "nonValidTokenIds" => [2]} in result[
               "sanbaseNft"
             ]["nftData"]
    end)
  end

  test "when there are no nfts - return false", context do
    mock_fun =
      [
        fn -> %{valid: [], non_valid: []} end
      ]
      |> Sanbase.Mock.wrap_consecutives(arity: 1)

    Sanbase.Mock.prepare_mock(SanbaseNFT, :nft_subscriptions_data, mock_fun)
    |> Sanbase.Mock.run_with_mocks(fn ->
      result = sanbase_nft(context.conn)
      refute result["sanbaseNft"]["hasValidNft"]
      refute result["sanbaseNft"]["hasNonValidNft"]
      assert result["sanbaseNft"]["nftCount"] == 0
      assert result["sanbaseNft"]["nonValidNftCount"] == 0
    end)
  end

  def sanbase_nft(conn) do
    query = """
    {
      currentUser {
        sanbaseNft {
          hasValidNft
          hasNonValidNft
          nftData {
            address
            tokenIds
            nonValidTokenIds
          }
          nftCount
          nonValidNftCount
        }
      }
    }
    """

    execute_query(conn, query, "currentUser")
  end
end
