defmodule Sanbase.Billing.Subscription.Stats do
  @moduledoc false
  import Ecto.Query

  alias Sanbase.Billing.Plan
  alias Sanbase.Billing.Subscription
  alias Sanbase.Billing.Subscription.Query
  alias Sanbase.Repo

  def user_active_subscriptions_map do
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
    |> Map.new(fn {user_id, products} ->
      {
        user_id,
        Enum.map_join(products, ", ", & &1.product)
      }
    end)
  end

  def all_user_subscriptions_map do
    Subscription
    |> Repo.all()
    |> Repo.preload(:plan)
    |> Enum.map(fn s ->
      %{
        user_id: s.user_id,
        id: s.id,
        plan: s.plan,
        product: s.plan.product_id,
        status: s.status,
        trial_end: s.trial_end
      }
    end)
    |> Enum.group_by(& &1.user_id)
  end

  def duplicate_sanbase_subscriptions do
    from(
      s in Subscription,
      join: p in Plan,
      on: s.plan_id == p.id,
      where:
        p.product_id == 2 and s.status in ["active", "trialing", "past_due"] and
          not is_nil(s.stripe_id),
      group_by: [s.user_id, p.product_id],
      having: count(s.id) >= 2,
      select: {s.user_id, count(s.id)}
    )
    |> Repo.all()
    |> Enum.map(fn {user_id, _} ->
      Repo.all(
        from(s in Subscription,
          join: p in Plan,
          on: s.plan_id == p.id,
          where:
            s.user_id == ^user_id and p.product_id == 2 and s.status in ["active", "trialing", "past_due"] and
              not is_nil(s.stripe_id),
          select: {s.id, s.stripe_id, s.plan_id, s.status, s.inserted_at},
          order_by: [desc: s.inserted_at]
        )
      )
    end)
  end
end
