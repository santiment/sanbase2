defmodule Sanbase.Billing.Subscription.Query do
  import Ecto.Query

  @preload_fields [:user, plan: [:product]]

  # only with status `active` and `past_due`
  def all_active_subscriptions(query) do
    from(q in query, where: q.status in ["active", "past_due"])
  end

  def all_active_subscriptions_for_plan(query, plan_id) do
    query = all_active_subscriptions(query)
    from(q in query, where: q.plan_id == ^plan_id)
  end

  def all_active_subscriptions_for_product(query, product_id) do
    query
    |> all_active_subscriptions()
    |> filter_product_id(product_id)
  end

  def user_has_any_subscriptions_for_product(query, user_id, product_id) do
    query
    |> filter_user(user_id)
    |> filter_product_id(product_id)
  end

  # with status `active`, `past_due`, `trialing`
  def all_active_and_trialing_subscriptions(query) do
    from(q in query, where: q.status in ["active", "past_due", "trialing"])
  end

  def all_active_and_trialing_subscriptions_for_plans(query, plans) when is_list(plans) do
    query = all_active_and_trialing_subscriptions(query)
    from(q in query, where: q.plan_id in ^plans)
  end

  def liquidity_subscriptions(query) do
    from(q in query, where: is_nil(q.stripe_id))
  end

  def filter_user(query, user_id) do
    from(q in query, where: q.user_id == ^user_id)
  end

  def filter_product_id(query, product_id) do
    from(s in query, join: p in assoc(s, :plan), where: p.product_id == ^product_id)
  end

  def select_product_id(query) do
    from(s in query, join: p in assoc(s, :plan), select: p.product_id)
  end

  def join_plan_and_product(query) do
    from(
      q in query,
      join: p in assoc(q, :plan),
      join: pr in assoc(p, :product),
      preload: [plan: {p, product: pr}]
    )
  end

  def preload(query, preloads \\ @preload_fields) do
    from(query, preload: ^preloads)
  end

  def last_subscription_for_product(query, product_id) do
    from(q in query,
      where: q.plan_id in fragment("SELECT id FROM plans WHERE product_id = ?", ^product_id),
      order_by: [desc: q.id],
      limit: 1
    )
  end

  def order_by(query) do
    from(q in query, order_by: [desc: q.id])
  end
end
