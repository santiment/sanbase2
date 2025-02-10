defmodule Sanbase.Billing.Subscription.SanbaseNFT do
  @moduledoc false
  alias Sanbase.Accounts.EthAccount
  alias Sanbase.Billing.Subscription
  alias Sanbase.SmartContracts.SanbaseNFT
  alias Sanbase.SmartContracts.SanbaseNFTInterface

  @doc ~s"""
  Create NFT subscription for users who have valid NFTs and no active Sanbase subscription
  """
  def maybe_create do
    eth_accounts = EthAccount.all()
    addresses = Enum.map(eth_accounts, & &1.address)
    address_to_user_id_map = Map.new(eth_accounts, &{&1.address, &1.user_id})

    addresses
    |> Enum.chunk_every(100)
    |> Enum.each(fn addr_chunk ->
      maybe_create_nft_subscription(addr_chunk, address_to_user_id_map)
    end)
  end

  def maybe_remove do
    :burning_nft
    |> Subscription.NFTSubscription.list_nft_subscriptions()
    |> Enum.each(fn nft_subscription ->
      resp = nft_subscriptions(nft_subscription.user_id)

      if !resp.has_valid_nft do
        Subscription.NFTSubscription.remove_nft_subscription(nft_subscription)
      end
    end)
  end

  # Private functions

  defp maybe_create_nft_subscription(addresses, address_to_user_id_map) do
    balances = balances(addresses)

    user_ids =
      addresses
      |> Enum.zip(balances)
      |> Enum.filter(fn {_, balance} -> balance > 0 end)
      |> Enum.map(fn {address, _} -> Map.get(address_to_user_id_map, address) end)

    Enum.filter(user_ids, fn user_id ->
      # TODO: Optimize so it's not called once per user_id?
      resp = nft_subscriptions(user_id)

      valid_nft? = resp.has_valid_nft

      no_active_sanbase_sub? = not Subscription.user_has_active_sanbase_subscriptions?(user_id)

      if valid_nft? and no_active_sanbase_sub? do
        Subscription.NFTSubscription.create_nft_subscription(
          user_id,
          :burning_nft,
          Timex.shift(DateTime.utc_now(), days: 30)
        )
      end
    end)
  end

  defp balances(addresses) do
    SanbaseNFT.balances_of(addresses)
  end

  defp nft_subscriptions(user_id) do
    SanbaseNFTInterface.nft_subscriptions(user_id)
  end
end
