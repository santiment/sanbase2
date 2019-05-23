defmodule Sanbase.Pricing.Subscription do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Pricing.{Product, Plan, Subscription}
  alias Sanbase.Pricing.Plan.AccessSeed
  alias Sanbase.Auth.User
  alias Sanbase.Repo

  require Logger

  schema "subscriptions" do
    field(:stripe_id, :string)
    belongs_to(:user, User)
    belongs_to(:plan, Plan)
  end

  def changeset(%Subscription{} = subscription, attrs \\ %{}) do
    subscription
    |> cast(attrs, [:plan_id, :user_id, :stripe_id])
  end

  def list_product_with_plans do
    products =
      Product
      |> Repo.all()
      |> Repo.preload(:plans)

    {:ok, products}
  end

  def user_subscriptions(user) do
    from(s in Subscription, where: s.user_id == ^user.id, order_by: [desc: s.id])
    |> Repo.all()
    |> Repo.preload(plan: [:product])
  end

  def current_subscription(user) do
    user
    |> user_subscriptions()
    |> List.first()
  end

  def has_access?(subscription, query) do
    case is_restricted?(query) do
      true -> subscription_access?(subscription, query)
      false -> true
    end
  end

  def historical_data_in_days(subscription) do
    subscription.plan.access["historical_data_in_days"]
  end

  def is_restricted?(query) do
    free = AccessSeed.free()[:metrics]
    all = AccessSeed.all_restricted_metrics()

    query in (all -- free)
  end

  def plan_name(subscription) do
    subscription.plan.name
  end

  def subscribe(user_id, card_token, plan_id) do
    with %User{} = user <- Repo.get(User, user_id),
         %Plan{} = plan <- Repo.get(Plan, plan_id),
         {:ok, _} <- create_or_update_stripe_customer(user, card_token),
         {:ok, stripe_subscription} <- create_stripe_subscription(user, plan) do
      create_subscription(stripe_subscription, user, plan)
    else
      nil ->
        {:error, "Can't find user user or plan with provided ids"}

      {:error, reason} ->
        Logger.error(inspect(reason))
    end
  end

  defp create_or_update_stripe_customer(%User{stripe_customer_id: stripe_id} = user, card_token)
       when is_nil(stripe_id) do
    create_stripe_customer(user, card_token)
    |> case do
      {:ok, stripe_customer} ->
        user
        |> User.changeset(%{stripe_customer_id: stripe_customer.id})
        |> Repo.update()

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_or_update_stripe_customer(%User{stripe_customer_id: stripe_id} = user, card_token)
       when is_binary(stripe_id) do
    update_stripe_customer(user, card_token)
  end

  defp create_stripe_customer(user, card_token) do
    Stripe.Customer.create(%{
      description: user.username,
      email: user.email,
      source: card_token
    })
  end

  defp update_stripe_customer(user, card_token) do
    Stripe.Customer.update(user.stripe_customer_id, %{source: card_token})
  end

  defp create_stripe_subscription(user, plan) do
    subscription = %{
      customer: user.stripe_customer_id,
      items: [%{plan: plan.stripe_id}]
    }

    user
    |> User.san_balance!()
    |> percent_off()
    |> update_subscription_with_coupon(subscription)
    |> Stripe.Subscription.create()
  end

  defp create_subscription(stripe_subscription, user, plan) do
    %Subscription{}
    |> Subscription.changeset(%{
      stripe_id: stripe_subscription.id,
      user_id: user.id,
      plan_id: plan.id
    })
    |> Repo.insert()
  end

  defp update_subscription_with_coupon(nil, subscription), do: subscription

  defp update_subscription_with_coupon(percent_off, subscription) do
    {:ok, coupon} = Stripe.Coupon.create(%{percent_off: percent_off, duration: "forever"})
    Map.put(subscription, :coupon, coupon)
  end

  defp percent_off(balance) when balance >= 1000, do: 20
  defp percent_off(balance) when balance >= 200, do: 4
  defp percent_off(_), nil

  defp subscription_access?(nil, _query), do: true

  defp subscription_access?(subscription, query) do
    query in subscription.plan.access["metrics"]
  end
end
