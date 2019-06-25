defmodule Sanbase.Pricing.Subscription do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Pricing.{Product, Plan, Subscription}
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

  schema "subscriptions" do
    field(:stripe_id, :string)
    field(:active, :boolean, null: false, default: false)
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
      :active,
      :current_period_end,
      :cancel_at_period_end
    ])
  end

  def product_with_plans do
    products =
      Product
      |> Repo.all()
      |> Repo.preload(:plans)

    {:ok, products}
  end

  def user_subscriptions(user) do
    user
    |> user_subscriptions_query()
    |> Repo.all()
    |> Repo.preload(plan: [:product])
  end

  def current_subscription(user, product_id) do
    user
    |> user_subscriptions_query()
    |> last_subscription_for_product_query(product_id)
    |> Repo.one()
    |> Repo.preload(plan: [:product])
  end

  def has_access?(subscription, query) do
    case needs_advanced_plan?(query) do
      true -> subscription_access?(subscription, query)
      false -> true
    end
  end

  def historical_data_in_days(subscription) do
    subscription.plan.access["historical_data_in_days"]
  end

  def is_restricted?(query) do
    query in AccessSeed.all_restricted_metrics()
  end

  def needs_advanced_plan?(query) do
    advanced_metrics = AccessSeed.advanced_metrics()
    standart_metrics = AccessSeed.standart_metrics()

    query in advanced_metrics and query not in standart_metrics
  end

  def plan_name(subscription) do
    subscription.plan.name
  end

  def subscribe(user_id, card_token, plan_id) do
    with {:user?, %User{} = user} <- {:user?, Repo.get(User, user_id)},
         {:plan?, %Plan{} = plan} <- {:plan?, Repo.get(Plan, plan_id)},
         {:ok, _} <- create_or_update_stripe_customer(user, card_token),
         {:ok, stripe_subscription} <- create_stripe_subscription(user, plan),
         {:ok, subscription} <- create_subscription_db(stripe_subscription, user, plan) do
      {:ok, subscription |> Repo.preload(plan: [:product])}
    else
      result ->
        handle_subscription_error_result(result, "Subscription attempt failed", %{
          user_id: user_id,
          plan_id: plan_id
        })
    end
  end

  @doc """
  Upgrade or Downgrade plan:
  https://stripe.com/docs/billing/subscriptions/upgrading-downgrading#switching
  """
  def update_subscription(user_id, plan_id) do
    with {:user?, %User{} = user} <- {:user?, Repo.get(User, user_id)},
         {:plan?, %Plan{} = plan} <- {:plan?, Repo.get(Plan, plan_id)},
         {:current_subscription?, current_subscription} when not is_nil(current_subscription) <-
           {:current_subscription?, current_subscription(user, Product.sanbase_api())},
         {:ok, item_id} <-
           StripeApi.get_subscription_first_item_id(current_subscription.stripe_id),

         # Note: that will generate dialyzer error because the spec is wrong.
         # More info here: https://github.com/code-corps/stripity_stripe/pull/499
         {:ok, _} <-
           StripeApi.update_subscription(current_subscription.stripe_id, %{
             items: [
               %{
                 id: item_id,
                 plan: plan.stripe_id
               }
             ]
           }),
         {:ok, subscription} <-
           update_subscription_db(current_subscription.id, %{plan_id: plan_id}) do
      {:ok, subscription |> Repo.preload(plan: [:product])}
    else
      result ->
        handle_subscription_error_result(result, "Upgrade/Downgrade failed", %{
          user_id: user_id,
          plan_id: plan_id
        })
    end
  end

  @doc """
  Cancel subscription:
  https://stripe.com/docs/billing/subscriptions/canceling-pausing#canceling
  """
  def cancel_subscription(user_id) do
    with {:user?, %User{} = user} <- {:user?, Repo.get(User, user_id)},
         {:current_subscription?, current_subscription} when not is_nil(current_subscription) <-
           {:current_subscription?, current_subscription(user, Product.sanbase_api())},
         {:ok, _} <-
           StripeApi.cancel_subscription(current_subscription.stripe_id),
         {:ok, _} <- update_subscription_db(current_subscription, %{cancel_at_period_end: true}) do
      {:ok,
       %{
         scheduled_for_cancellation: true,
         scheduled_for_cancellation_at: current_subscription.current_period_end
       }}
    else
      result ->
        handle_subscription_error_result(
          result,
          "Canceling subscription failed",
          %{user_id: user_id}
        )
    end
  end

  defp handle_subscription_error_result(result, log_message, params) do
    case result do
      {:user?, _} ->
        reason = "Cannnot find user with id #{params.user_id}"
        Logger.error("#{log_message} - reason: #{reason}")
        {:error, reason}

      {:plan?, _} ->
        reason = "Cannnot find plan with id #{params.plan_id}"
        Logger.error("#{log_message} - reason: #{reason}")
        {:error, reason}

      {:current_subscription?, nil} ->
        reason =
          "Current user with user id: #{params.user_id} does not have active subscriptions."

        Logger.error("#{log_message} - reason: #{reason}")
        {:error, reason}

      {:error, reason} ->
        Logger.error("#{log_message} - reason: #{inspect(reason)}")
        {:error, @generic_error_message}
    end
  end

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
      current_period_end: stripe_subscription.current_period_end
    })
    |> Repo.insert()
  end

  defp update_subscription_db(current_subscription, params) do
    current_subscription
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

  defp last_subscription_for_product_query(query, product_id) do
    from(s in query,
      where: s.plan_id in fragment("select id from plans where product_id = ?", ^product_id),
      limit: 1
    )
  end
end
