defmodule Sanbase.Billing.Subscription.Query do
  import Ecto.Query

  # only with status `active` and `past_due`
  def all_active_subscriptions_for_plan_query(query, plan_id) do
    from(q in query,
      where:
        q.plan_id == ^plan_id and
          q.status in ["active", "past_due"]
    )
  end

  # with status `active`, `past_due`, `trialing`
  def all_active_and_trialing_subscriptions_for_plan_query(query, plan_id) do
    from(q in query,
      where:
        q.plan_id == ^plan_id and
          q.status in ["active", "past_due", "trialing"]
    )
  end

  def free_subscriptions_query(query) do
    from(q in query, where: is_nil(q.stripe_id))
  end

  def filter_user_query(query, user_id) do
    from(q in query, where: q.user_id == ^user_id)
  end
end
