defmodule Sanbase.Billing.Subscription.SanbaseNFT do
  alias Sanbase.Accounts.EthAccount
  alias Sanbase.SmartContracts.SanbaseNFTInterface
  alias Sanbase.SmartContracts.SanbaseNFT
  alias Sanbase.Billing.Subscription

  @doc ~s"""
  Create NFT subscription for users who have valid NFTs and no active Sanbase subscription
  """
  def maybe_create() do
    eth_accounts = EthAccount.all()
    addresses = eth_accounts |> Enum.map(& &1.address)
    address_to_user_id_map = Map.new(eth_accounts, &{&1.address, &1.user_id})

    addresses
    |> Enum.chunk_every(100)
    |> Enum.each(fn addr_chunk ->
      maybe_create_nft_subscription(addr_chunk, address_to_user_id_map)
    end)
  end

  def maybe_remove() do
    Subscription.NFTSubscription.list_nft_subscriptions(:burning_nft)
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
      Enum.zip(addresses, balances)
      |> Enum.filter(fn {_, balance} -> balance > 0 end)
      |> Enum.map(fn {address, _} -> Map.get(address_to_user_id_map, address) end)

    user_ids
    |> Enum.filter(fn user_id ->
      # TODO: Optimize so it's not called once per user_id?
      resp = nft_subscriptions(user_id)

      valid_nft? = resp.has_valid_nft

      no_active_sanbase_sub? = not Subscription.user_has_active_sanbase_subscriptions?(user_id)

      if valid_nft? and no_active_sanbase_sub? do
        Subscription.NFTSubscription.create_nft_subscription(
          user_id,
          :burning_nft,
          Timex.shift(Timex.now(), days: 30)
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
