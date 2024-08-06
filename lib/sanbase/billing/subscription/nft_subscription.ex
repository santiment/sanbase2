defmodule Sanbase.Billing.Subscription.NFTSubscription do
  alias Sanbase.Repo
  alias Sanbase.Billing.Subscription

  @sanbase_pro_plan Sanbase.Billing.Plan.Metadata.current_san_stake_plan()

  def run() do
    # Runs every 10 minutes, configured in scheduler_config.exs
    if prod?() do
      Subscription.SanbaseNFT.maybe_create()
      Subscription.SanbaseNFT.maybe_remove()

      Subscription.SanrNFT.maybe_create()
      Subscription.SanrNFT.maybe_remove()
    else
      :ok
    end
  end

  @doc ~s"""

  """
  def create_nft_subscription(user_id, type, current_period_end) do
    Subscription.create(
      %{
        user_id: user_id,
        plan_id: @sanbase_pro_plan,
        status: "active",
        current_period_end: current_period_end,
        type: type
      },
      event_args: %{type: :nft_subscription}
    )
  end

  @doc ~s"""

  """
  def remove_nft_subscription(nft_subscription) do
    Subscription.delete(
      nft_subscription,
      event_args: %{type: :nft_subscription}
    )
  end

  def list_nft_subscriptions(type) do
    Subscription
    |> Subscription.Query.all_active_subscriptions_for_plan(@sanbase_pro_plan)
    |> Subscription.Query.nft_subscriptions(type)
    |> Repo.all()
  end

  # Private functions

  defp prod?() do
    Sanbase.Utils.Config.module_get(Sanbase, :deployment_env) in ["prod"]
  end
end
