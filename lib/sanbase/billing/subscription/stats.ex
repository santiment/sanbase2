defmodule Sanbase.Billing.Subscription.Stats do
  alias Sanbase.Billing.Plan
  alias Sanbase.Billing.Subscription
  alias Sanbase.Billing.Subscription.Query
  alias Sanbase.Repo

  def user_active_subscriptions_map() do
    Subscription
    |> Query.all_active_subscriptions()
    |> Query.preload(plan: [:product])
    |> Repo.all()
    |> Enum.map(fn subscription ->
      %{
        user_id: subscription.user_id,
        product: Plan.plan_full_name(subscription.plan)
      }
    end)
    |> Enum.group_by(& &1.user_id)
    |> Enum.into(%{}, fn {user_id, products} ->
      {
        user_id,
        Enum.map(products, & &1.product) |> Enum.join(", ")
      }
    end)
  end
end
