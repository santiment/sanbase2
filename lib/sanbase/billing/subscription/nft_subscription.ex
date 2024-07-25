defmodule Sanbase.Billing.Subscription.NFTSubscription do
  alias Sanbase.Repo
  alias Sanbase.Accounts.EthAccount
  alias Sanbase.SmartContracts.SanbaseNFTInterface
  alias Sanbase.SmartContracts.SanbaseNFT
  alias Sanbase.Billing.Subscription
  alias Sanbase.Billing.Subscription.LiquiditySubscription

  @sanbase_pro_plan Sanbase.Billing.Plan.Metadata.current_san_stake_plan()

  # Run every 10 minutes
  def run() do
    if prod?() do
      maybe_create()
      maybe_remove()
    else
      :ok
    end
  end

  @doc ~s"""
  Create NFT subscription for users who have valid NFTs and no active Sanbase subscription
  """
  def maybe_create() do
    eth_accounts = Repo.all(EthAccount)
    addresses = eth_accounts |> Enum.map(& &1.address)
    address_to_user_id_map = Map.new(eth_accounts, &{&1.address, &1.user_id})

    addresses
    |> Enum.chunk_every(100)
    |> Enum.each(fn addr_chunk ->
      maybe_create_nft_subscription(addr_chunk, address_to_user_id_map)
    end)
  end

  def maybe_remove() do
    list_nft_subscriptions()
    |> Enum.each(fn nft_subscription ->
      resp = nft_subscriptions(nft_subscription.user_id)

      if !resp.has_valid_nft do
        remove_nft_subscription(nft_subscription)
      end
    end)
  end

  def create_nft_subscription(user_id) do
    Subscription.create(
      %{
        user_id: user_id,
        plan_id: @sanbase_pro_plan,
        status: "active",
        current_period_end: Timex.shift(Timex.now(), days: 30),
        type: :burning_nft
      },
      event_args: %{type: :nft_subscription}
    )
  end

  def remove_nft_subscription(nft_subscription) do
    Subscription.delete(
      nft_subscription,
      event_args: %{type: :nft_subscription}
    )
  end

  def list_nft_subscriptions() do
    Subscription
    |> Subscription.Query.all_active_subscriptions_for_plan(@sanbase_pro_plan)
    |> Subscription.Query.nft_subscriptions()
    |> Repo.all()
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
      resp = nft_subscriptions(user_id)

      valid_nft? = resp.has_valid_nft

      no_active_sanbase_sub? =
        not LiquiditySubscription.user_has_active_sanbase_subscriptions?(user_id)

      if valid_nft? and no_active_sanbase_sub? do
        create_nft_subscription(user_id)
      end
    end)
  end

  defp balances(addresses) do
    SanbaseNFT.balances_of(addresses)
  end

  defp nft_subscriptions(user_id) do
    SanbaseNFTInterface.nft_subscriptions(user_id)
  end

  defp prod?() do
    Sanbase.Utils.Config.module_get(Sanbase, :deployment_env) in ["prod"]
  end
end
