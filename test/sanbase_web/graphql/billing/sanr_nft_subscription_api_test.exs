defmodule Sanbase.Billing.SanrNftSubscriptionsApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Mox
  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Accounts.EthAccount
  alias Sanbase.Billing.Subscription

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    user = insert(:user)

    address = Sanbase.BlockchainAddress.to_internal_format("0x23918E95d234eEc054566DDe0841d69311814495")

    start_date = DateTime.utc_now()
    end_date = start_date |> DateTime.shift(month: 12) |> DateTime.truncate(:second)

    %{
      user: user,
      conn: setup_jwt_auth(build_conn(), user),
      address: address,
      start_date: start_date,
      end_date: end_date
    }
  end

  test "checkSanrNftSubscriptionEligibility", context do
    query = """
    { checkSanrNftSubscriptionEligibility }
    """

    Req
    |> Sanbase.Mock.prepare_mock(
      :get,
      fn req, _params ->
        case req.options.base_url do
          "https://zksync-mainnet.g.alchemy.com" ->
            Sanbase.SanrNFTMocks.get_owners_for_contract_mock(context.address)

          "https://api.sanr.app/v1/SanbaseSubscriptionNFTCollection/all" ->
            Sanbase.SanrNFTMocks.sanr_nft_collections_mock(context.start_date, context.end_date)
        end
      end
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      # The user does not have an active subscription, not such will be granted
      assert Subscription.user_has_active_sanbase_subscriptions?(context.user.id) == false
      # The user has no account, so their are not eligible
      result =
        context.conn
        |> post("/graphql", query_skeleton(query))
        |> json_response(200)
        |> get_in(["data", "checkSanrNftSubscriptionEligibility"])

      assert result == false

      # Add a random address to the account without NFT, still not eligible
      random_address = "0x" <> rand_hex_str(38)
      {:ok, _} = EthAccount.create(context.user.id, random_address)

      result =
        context.conn
        |> post("/graphql", query_skeleton(query))
        |> json_response(200)
        |> get_in(["data", "checkSanrNftSubscriptionEligibility"])

      assert result == false

      # Add the address that actually holds an NFT, user is not eligible
      {:ok, _} = EthAccount.create(context.user.id, context.address)

      result =
        context.conn
        |> post("/graphql", query_skeleton(query))
        |> json_response(200)
        |> get_in(["data", "checkSanrNftSubscriptionEligibility"])

      assert result == true

      # The user does not have an active subscription, not such will be granted
      assert Subscription.user_has_active_sanbase_subscriptions?(context.user.id) == false
    end)
  end

  test "obtainSanrNftSubscription", context do
    expect(Sanbase.Email.MockMailjetApi, :subscribe, fn _, _ -> :ok end)

    mutation = """
    mutation{
      obtainSanrNftSubscription {
        type
      }
    }
    """

    Req
    |> Sanbase.Mock.prepare_mock(
      :get,
      fn req, _params ->
        case req.options.base_url do
          "https://zksync-mainnet.g.alchemy.com" ->
            Sanbase.SanrNFTMocks.get_owners_for_contract_mock(context.address)

          "https://api.sanr.app/v1/SanbaseSubscriptionNFTCollection/all" ->
            Sanbase.SanrNFTMocks.sanr_nft_collections_mock(context.start_date, context.end_date)
        end
      end
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      # The user does not have an active subscription
      assert Subscription.user_has_active_sanbase_subscriptions?(context.user.id) == false
      # The user has no account, so their are not eligible
      error_msg =
        context.conn
        |> post("/graphql", mutation_skeleton(mutation))
        |> json_response(200)
        |> get_in(["errors", Access.at(0), "message"])

      assert error_msg =~ "user does not have any blockchain addresses connected"
      # Add the address that actually holds an NFT, user is not eligible
      {:ok, _} = EthAccount.create(context.user.id, context.address)

      result =
        context.conn
        |> post("/graphql", mutation_skeleton(mutation))
        |> json_response(200)
        |> get_in(["data", "obtainSanrNftSubscription"])

      # Now a subscription has been created
      assert result == %{"type" => "SANR_POINTS_NFT"}

      # The user now has an active subscription
      assert Subscription.user_has_active_sanbase_subscriptions?(context.user.id) == true
    end)
  end
end
