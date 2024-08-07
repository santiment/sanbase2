defmodule Sanbase.Billing.SanrNFTSubscriptionTest do
  use Sanbase.DataCase, async: false
  import Sanbase.Factory

  alias Sanbase.Accounts.EthAccount
  alias Sanbase.Billing.Subscription

  setup do
    user = insert(:user)

    address =
      "0x23918E95d234eEc054566DDe0841d69311814495"
      |> Sanbase.BlockchainAddress.to_internal_format()

    {:ok, _} = EthAccount.create(user.id, address)
    start_date = DateTime.utc_now()
    end_date = DateTime.shift(start_date, month: 12) |> DateTime.truncate(:second)

    %{
      user: user,
      address: address,
      start_date: start_date,
      end_date: end_date
    }
  end

  test "create subscription", context do
    %{user: user, address: address, start_date: start_date, end_date: end_date} = context

    Sanbase.Mock.prepare_mock(
      Req,
      :get,
      fn req, _params ->
        case req.options.base_url do
          "https://zksync-mainnet.g.alchemy.com" ->
            get_owners_for_contract_mock(address)

          "https://sanrnew-api.production.internal.santiment.net/api/v1/SanbaseSubscriptionNFTCollection/all" ->
            sanr_nft_collections_mock(start_date, end_date)
        end
      end
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      assert Subscription.user_has_active_sanbase_subscriptions?(user.id) == false

      [{:ok, subscription}] = Sanbase.Billing.Subscription.SanrNFT.maybe_create()

      assert subscription.user_id == user.id
      assert subscription.current_period_end == end_date
      assert subscription.type == :sanr_points_nft
      assert subscription.status == :active

      assert Subscription.user_has_active_sanbase_subscriptions?(user.id) == true
    end)
  end

  test "remove subscription", %{user: user} do
    end_date = DateTime.shift(DateTime.utc_now(), month: 12) |> DateTime.truncate(:second)
    Subscription.NFTSubscription.create_nft_subscription(user.id, :sanr_points_nft, end_date)

    Sanbase.Mock.prepare_mock2(
      &Sanbase.SmartContracts.SanrNFT.get_all_nft_owners/0,
      {:ok, %{}}
    )
    |> Sanbase.Mock.prepare_mock2(
      &Sanbase.SmartContracts.SanrNFT.get_all_nft_expiration_dates/0,
      {:ok, %{}}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      assert Subscription.user_has_active_sanbase_subscriptions?(user.id) == true

      [{:ok, removed_subscription}] = Sanbase.Billing.Subscription.SanrNFT.maybe_remove()
      assert removed_subscription.user_id == user.id
      assert removed_subscription.type == :sanr_points_nft

      assert Subscription.user_has_active_sanbase_subscriptions?(user.id) == false
    end)
  end

  defp get_owners_for_contract_mock(address) do
    {:ok,
     %Req.Response{
       status: 200,
       headers: %{},
       body: %{
         "owners" => [
           %{
             "ownerAddress" => address,
             "tokenBalances" => [
               %{"balance" => "1", "tokenId" => "1"},
               %{"balance" => "1", "tokenId" => "2"}
             ]
           }
         ],
         "pageKey" => nil
       },
       trailers: %{},
       private: %{}
     }}
  end

  defp sanr_nft_collections_mock(start_date, end_date) do
    {:ok,
     %Req.Response{
       status: 200,
       headers: %{},
       body: [
         %{
           "id" => 1,
           "sanr_points_amount" => 10000,
           "subscription_end_date" => end_date,
           "subscription_start_date" => start_date
         },

         # This one is expired. Added here so we can test what happens when
         # one address holds multiple NFTs
         %{
           "id" => 2,
           "sanr_points_amount" => 10000,
           "subscription_end_date" => ~U[2024-05-05 00:00:00Z],
           "subscription_start_date" => ~U[2023-05-05 00:00:00Z]
         }
       ],
       trailers: %{},
       private: %{}
     }}
  end
end
