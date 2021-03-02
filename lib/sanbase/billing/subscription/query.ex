defmodule Sanbase.Billing.Subscription.Query do
  import Ecto.Query

  @preload_fields [:user, plan: [:product]]

  # only with status `active` and `past_due`
  def all_active_subscriptions_query(query) do
    from(q in query, where: q.status in ["active", "past_due"])
  end

  def all_active_subscriptions_for_plan_query(query, plan_id) do
    query = all_active_subscriptions_query(query)
    from(q in query, where: q.plan_id == ^plan_id)
  end

  # with status `active`, `past_due`, `trialing`
  def all_active_and_trialing_subscriptions_query(query) do
    from(q in query, where: q.status in ["active", "past_due", "trialing"])
  end

  def all_active_and_trialing_subscriptions_for_plan_query(query, plan_id) do
    query = all_active_and_trialing_subscriptions_query(query)
    from(q in query, where: q.plan_id == ^plan_id)
  end

  def liquidity_subscriptions_query(query) do
    from(q in query, where: is_nil(q.stripe_id))
  end

  def filter_user_query(query, user_id) do
    from(q in query, where: q.user_id == ^user_id)
  end

  def select_product_id_query(query) do
    from(s in query, join: p in assoc(s, :plan), select: p.product_id)
  end

  def join_plan_and_product_query(query) do
    from(
      q in query,
      join: p in assoc(q, :plan),
      join: pr in assoc(p, :product),
      preload: [plan: {p, product: pr}]
    )
  end

  def preload_query(query, preloads \\ @preload_fields) do
    from(query, preload: ^preloads)
  end

  def last_subscription_for_product_query(query, product_id) do
    from(q in query,
      where: q.plan_id in fragment("SELECT id FROM plans WHERE product_id = ?", ^product_id),
      order_by: [desc: q.id],
      limit: 1
    )
  end

  def order_by_query(query) do
    from(q in query, order_by: [desc: q.id])
  end
end
