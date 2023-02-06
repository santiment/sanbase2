defmodule Sanbase.Billing.Subscription.NFTSubscription do
  alias Sanbase.Repo
  alias Sanbase.Accounts.EthAccount
  alias Sanbase.SmartContracts.SanbaseNFTInterface
  alias Sanbase.SmartContracts.SanbaseNFT
  alias Sanbase.Billing.Subscription
  alias Sanbase.Billing.Subscription.LiquiditySubscription

  @sanbase_pro_plan Sanbase.Billing.Plan.Metadata.current_san_stake_plan()

  # Run every 10 minutes
  def run do
    maybe_create()
    maybe_remove()
  end

  def maybe_create do
    addresses = Repo.all(EthAccount) |> Enum.map(& &1.address)

    addresses
    |> Enum.chunk_every(100)
    |> Enum.each(fn addr_chunk ->
      balances = balances(addr_chunk)

      user_ids =
        Enum.zip(addr_chunk, balances)
        |> Enum.filter(fn {_, balance} -> balance > 0 end)
        |> Enum.map(fn {address, _} -> EthAccount.by_address(address).user_id end)

      user_ids
      |> Enum.filter(fn user_id ->
        resp = nft_subscriptions(user_id)

        if resp.has_valid_nft and
             !LiquiditySubscription.user_has_active_sanbase_subscriptions?(user_id) do
          create_nft_subscription(user_id)
        end
      end)
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

  # Sleep because testnet goerly alchemy node is unreliable
  defp balances(addresses) do
    if is_dev_or_stage?(), do: Process.sleep(1000)
    SanbaseNFT.balances_of(addresses)
  end

  # Sleep because testnet goerly alchemy node is unreliable
  defp nft_subscriptions(user_id) do
    if is_dev_or_stage?(), do: Process.sleep(1000)
    SanbaseNFTInterface.nft_subscriptions(user_id)
  end

  defp is_dev_or_stage?() do
    Sanbase.Utils.Config.module_get(Sanbase, :deployment_env) in ["dev", "stage"]
  end
end
