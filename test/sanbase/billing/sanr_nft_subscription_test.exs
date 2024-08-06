defmodule Sanbase.Billing.SanrNFTSubscriptionTest do
  use Sanbase.DataCase, async: false
  import Sanbase.Factory

  alias Sanbase.Accounts.EthAccount
  alias Sanbase.Billing.Subscription

  test "create subscription" do
    user = insert(:user)
    address = "0x23918E95d234eEc054566DDe0841d69311814495"
    {:ok, _} = EthAccount.create(user.id, address)
    start_date = DateTime.utc_now()
    end_date = DateTime.shift(start_date, month: 12) |> DateTime.truncate(:second)

    Sanbase.Mock.prepare_mock2(
      &Sanbase.SmartContracts.SanrNFT.get_all_nft_owners/0,
      {:ok, %{address => %{token_id: 1}}}
    )
    |> Sanbase.Mock.prepare_mock2(
      &Sanbase.SmartContracts.SanrNFT.get_all_nft_expiration_dates/0,
      {:ok, %{1 => %{start_date: start_date, end_date: end_date}}}
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

  test "remove subscription" do
    user = insert(:user)
    address = "0x23918E95d234eEc054566DDe0841d69311814495"
    {:ok, _} = EthAccount.create(user.id, address)

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
end
