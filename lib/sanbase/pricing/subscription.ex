defmodule Sanbase.Pricing.Subscription do
  @moduledoc """
  Module for managing user subscriptions - create, upgrade/downgrade, cancel.
  Also containing some helper functions that take user subscription as argument and
  return some properties of the subscription plan.
  """
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Pricing.{Plan, Subscription}
  alias Sanbase.Pricing.Plan.AccessSeed
  alias Sanbase.Auth.User
  alias Sanbase.Repo
  alias Sanbase.StripeApi

  require Logger

  @generic_error_message """
  Current subscription attempt failed. Please, contact administrator of the site for more information.
  """
  @percent_discount_1000_san 20
  @percent_discount_200_san 4
  # After `current_period_end` timestamp passes there is some time until `invoice.payment_succeeded` event is generated
  # to update the field with new timestamp value. So we add 1 day gratis in which we should receive payment before
  # we decide that this subscription is not active.
  # Check for active subscription: current_period_end > Timex.now - @subscription_gratis_days
  @subscription_gratis_days 1

  schema "subscriptions" do
    field(:stripe_id, :string)
    field(:current_period_end, :utc_datetime)
    field(:cancel_at_period_end, :boolean, null: false, default: false)
    belongs_to(:user, User)
    belongs_to(:plan, Plan)
  end

  def generic_error_message, do: @generic_error_message

  def changeset(%Subscription{} = subscription, attrs \\ %{}) do
    subscription
    |> cast(attrs, [
      :plan_id,
      :user_id,
      :stripe_id,
      :current_period_end,
      :cancel_at_period_end
    ])
  end

  @doc """
  Subscribe user with card_token to a plan.

  - Create or update a Stripe customer with card details contained by the card_token param.
  - Create subscription record in Stripe.
  - Create a subscription record locally so we can check access control without calling Stripe.
  """
  def subscribe(user, card_token, plan) do
    with {:ok, %User{stripe_customer_id: stripe_customer_id} = user}
         when not is_nil(stripe_customer_id) <-
           create_or_update_stripe_customer(user, card_token),
         {:ok, stripe_subscription} <- create_stripe_subscription(user, plan),
         {:ok, subscription} <- create_subscription_db(stripe_subscription, user, plan) do
      {:ok, subscription |> Repo.preload(plan: [:product])}
    end
  end

  @doc """
  Upgrade or Downgrade plan:

  - Updates subcription in Stripe with new plan.
  - Updates local subscription
  Stripe docs:   https://stripe.com/docs/billing/subscriptions/upgrading-downgrading#switching
  """
  def update_subscription(subscription, plan) do
    with {:ok, item_id} <- StripeApi.get_subscription_first_item_id(subscription.stripe_id),
         # Note: that will generate dialyzer error because the spec is wrong.
         # More info here: https://github.com/code-corps/stripity_stripe/pull/499
         {:ok, _} <-
           StripeApi.update_subscription(subscription.stripe_id, %{
             items: [
               %{
                 id: item_id,
                 plan: subscription.plan.stripe_id
               }
             ]
           }),
         {:ok, updated_subscription} <-
           update_subscription_db(subscription, %{plan_id: plan.id}) do
      {:ok, updated_subscription |> Repo.preload([plan: [:product]], force: true)}
    end
  end

  @doc """
  Cancel subscription:

  Cancellation means scheduling for cancellation. It updates the `cancel_at_period_end` field which will cancel the
  subscription at `current_period_end`. That allows user to use the subscription for the time left that he has already paid for.
  https://stripe.com/docs/billing/subscriptions/canceling-pausing#canceling
  """
  def cancel_subscription(subscription) do
    with {:ok, _} <- StripeApi.cancel_subscription(subscription.stripe_id),
         {:ok, _} <- update_subscription_db(subscription, %{cancel_at_period_end: true}) do
      {:ok,
       %{
         is_scheduled_for_cancellation: true,
         scheduled_for_cancellation_at: subscription.current_period_end
       }}
    end
  end

  @doc """
  List all active user subscriptions with plans and products.
  """
  def user_subscriptions(user) do
    user
    |> user_subscriptions_query()
    |> active_subscriptions_query()
    |> Repo.all()
    |> Repo.preload(plan: [:product])
  end

  @doc """
  Current subscription is the last active subscription for a product.
  """
  def current_subscription(user, product_id) do
    user
    |> user_subscriptions_query()
    |> active_subscriptions_query()
    |> last_subscription_for_product_query(product_id)
    |> Repo.one()
    |> Repo.preload(plan: [:product])
  end

  @doc """
  By subscription and query name determines whether subscription can access the query.
  """
  def has_access?(subscription, query) do
    case needs_advanced_plan?(query) do
      true -> subscription_access?(subscription, query)
      false -> true
    end
  end

  @doc """
  How much historical days a subscription plan can access.
  """
  def historical_data_in_days(subscription) do
    subscription.plan.access["historical_data_in_days"]
  end

  @doc """
  Checks whether a query is in any plan.
  """
  def is_restricted?(query) do
    query in AccessSeed.all_restricted_metrics()
  end

  @doc """
  Query is in advanced subscription plans only
  """
  def needs_advanced_plan?(query) do
    advanced_metrics = AccessSeed.advanced_metrics()
    standart_metrics = AccessSeed.standart_metrics()

    query in advanced_metrics and query not in standart_metrics
  end

  def plan_name(subscription) do
    subscription.plan.name
  end

  # private functions

  defp create_or_update_stripe_customer(%User{stripe_customer_id: stripe_id} = user, card_token)
       when is_nil(stripe_id) do
    StripeApi.create_customer(user, card_token)
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
    StripeApi.update_customer(user, card_token)
    |> case do
      {:ok, _} ->
        {:ok, user}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_stripe_subscription(user, plan) do
    subscription = %{
      customer: user.stripe_customer_id,
      items: [%{plan: plan.stripe_id}]
    }

    user
    |> User.san_balance!()
    |> percent_discount()
    |> update_subscription_with_coupon(subscription)
    |> case do
      {:ok, subscription} ->
        StripeApi.create_subscription(subscription)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_subscription_db(stripe_subscription, user, plan) do
    %Subscription{}
    |> Subscription.changeset(%{
      stripe_id: stripe_subscription.id,
      user_id: user.id,
      plan_id: plan.id,
      active: true,
      current_period_end: DateTime.from_unix!(stripe_subscription.current_period_end)
    })
    |> Repo.insert()
  end

  def update_subscription_db(subscription, params) do
    subscription
    |> Subscription.changeset(params)
    |> Repo.update()
  end

  defp update_subscription_with_coupon(nil, subscription), do: subscription

  defp update_subscription_with_coupon(percent_off, subscription) do
    StripeApi.create_coupon(%{percent_off: percent_off, duration: "forever"})
    |> case do
      {:ok, coupon} ->
        {:ok, Map.put(subscription, :coupon, coupon.id)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp percent_discount(balance) when balance >= 1000, do: @percent_discount_1000_san
  defp percent_discount(balance) when balance >= 200, do: @percent_discount_200_san
  defp percent_discount(_), do: nil

  defp subscription_access?(nil, _query), do: false

  defp subscription_access?(subscription, query) do
    query in subscription.plan.access["metrics"]
  end

  defp user_subscriptions_query(user) do
    from(s in Subscription,
      where: s.user_id == ^user.id,
      order_by: [desc: s.id]
    )
  end

  # current_period_end > Timex.now - gratis days
  defp active_subscriptions_query(query) do
    from(s in query,
      where: s.current_period_end > ^Timex.shift(Timex.now(), days: -@subscription_gratis_days)
    )
  end

  defp last_subscription_for_product_query(query, product_id) do
    from(s in query,
      where: s.plan_id in fragment("select id from plans where product_id = ?", ^product_id),
      limit: 1
    )
  end
end
