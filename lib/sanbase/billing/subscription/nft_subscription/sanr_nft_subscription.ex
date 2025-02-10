defmodule Sanbase.Billing.Subscription.SanrNFT do
  @moduledoc false
  alias Sanbase.Accounts.EthAccount
  alias Sanbase.Billing.Subscription
  alias Sanbase.SmartContracts

  @doc ~s"""
  Create NFT subscription for users who have valid SanR NFTs and no active
  Sanbase subscription. The token must still be valid. Tokens expire 12
  months after they are minted
  """
  def maybe_create do
    {:ok, nft_owners} = SmartContracts.SanrNFT.get_all_nft_owners()
    {:ok, nft_metadata} = SmartContracts.SanrNFT.get_all_nft_expiration_dates()

    addresses = Map.keys(nft_owners)
    address_to_user_id_map = EthAccount.address_to_user_id_map(addresses)

    maybe_create_nft_subscriptions(nft_owners, nft_metadata, address_to_user_id_map)
  end

  @doc ~s"""
  Remove the subscription from the users who previously held valid SanR NFT tokens but no
  longer do.
  """
  def maybe_remove do
    {:ok, nft_owners} = SmartContracts.SanrNFT.get_all_nft_owners()

    addresses = Map.keys(nft_owners)
    address_to_user_id_map = EthAccount.address_to_user_id_map(addresses)

    maybe_remove_nft_subscriptions(address_to_user_id_map)
  end

  # Private functions

  defp maybe_create_nft_subscriptions(nft_owners, nft_metadata, address_to_user_id_map) do
    Enum.map(nft_owners, fn {address, %{token_id: token_id}} ->
      with user_id when is_integer(user_id) <- address_to_user_id_map[address],
           end_dt when is_struct(end_dt, DateTime) <- get_in(nft_metadata, [token_id, :end_date]),
           true <- Timex.before?(DateTime.utc_now(), end_dt),
           false <- Subscription.user_has_active_sanbase_subscriptions?(user_id) do
        # If the address holding a given token is associated with a user, the token is still valid,
        # and the user has no sanbase subscription - create a new one
        Subscription.NFTSubscription.create_nft_subscription(
          user_id,
          :sanr_points_nft,
          end_dt
        )
      end
    end)
  end

  defp maybe_remove_nft_subscriptions(address_to_user_id_map) do
    # Get all the active subscription of this type
    subscriptions = Subscription.NFTSubscription.list_nft_subscriptions(:sanr_points_nft)
    user_ids_with_subscription = Enum.map(subscriptions, & &1.user_id)

    # Get all the user ids who are holding the NFT at the moment.
    # Their subscription will be preserved
    user_ids_holding_nft = Map.values(address_to_user_id_map)

    # These  users had an NFT in the past but they no longer do. Their active
    # subscription will be cancelled
    user_ids_no_longer_owners = user_ids_with_subscription -- user_ids_holding_nft
    user_ids_no_longer_owners = MapSet.new(user_ids_no_longer_owners)

    Enum.map(subscriptions, fn subscription ->
      if subscription.user_id in user_ids_no_longer_owners do
        Subscription.NFTSubscription.remove_nft_subscription(subscription)
      end
    end)
  end
end
