defmodule Sanbase.Billing.Subscription do
  @moduledoc """
  Module for managing user subscriptions - create, upgrade/downgrade, cancel.
  Also containing some helper functions that take user subscription as argument and
  return some properties of the subscription plan.
  """
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Billing.Plan
  alias Sanbase.Billing.Plan.AccessChecker
  alias Sanbase.Auth.User
  alias Sanbase.Repo
  alias Sanbase.StripeApi

  require Logger

  @percent_discount_1000_san 20
  @percent_discount_200_san 4
  @generic_error_message """
  Current subscription attempt failed.
  Please, contact administrator of the site for more information.
  """
  @free_trial_days_for_coupons 14

  schema "subscriptions" do
    field(:stripe_id, :string)
    field(:current_period_end, :utc_datetime)
    field(:cancel_at_period_end, :boolean, null: false, default: false)
    field(:status, SubscriptionStatusEnum)

    belongs_to(:user, User)
    belongs_to(:plan, Plan)
  end

  def generic_error_message, do: @generic_error_message

  def changeset(%__MODULE__{} = subscription, attrs \\ %{}) do
    subscription
    |> cast(attrs, [
      :plan_id,
      :user_id,
      :stripe_id,
      :current_period_end,
      :cancel_at_period_end,
      :status
    ])
    |> foreign_key_constraint(:plan_id, name: :subscriptions_plan_id_fkey)
  end

  @spec free_subscription() :: %__MODULE__{}
  def free_subscription() do
    %__MODULE__{plan: Plan.free_plan()}
  end

  @doc """
  Subscribe user with card_token to a plan.

  - Create or update a Stripe customer with card details contained by the card_token param.
  - Create subscription record in Stripe.
  - Create a subscription record locally so we can check access control without calling Stripe.
  """
  def subscribe(user, card_token, plan, coupon \\ nil) do
    with {:ok, %User{stripe_customer_id: stripe_customer_id} = user}
         when not is_nil(stripe_customer_id) <-
           create_or_update_stripe_customer(user, card_token),
         {:ok, stripe_subscription} <- create_stripe_subscription(user, plan, coupon),
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
         {:ok, stripe_subscription} <-
           StripeApi.update_subscription(subscription.stripe_id, %{
             items: [
               %{
                 id: item_id,
                 plan: plan.stripe_id
               }
             ]
           }),
         {:ok, updated_subscription} <-
           sync_with_stripe_subscription(stripe_subscription, subscription) do
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
    with {:ok, stripe_subscription} <- StripeApi.cancel_subscription(subscription.stripe_id),
         {:ok, _} <- sync_with_stripe_subscription(stripe_subscription, subscription) do
      {:ok,
       %{
         is_scheduled_for_cancellation: true,
         scheduled_for_cancellation_at: subscription.current_period_end
       }}
    end
  end

  @doc """
  Renew cancelled subscription if `current_period_end` is not reached.

  https://stripe.com/docs/billing/subscriptions/canceling-pausing#reactivating-canceled-subscriptions
  """
  def renew_cancelled_subscription(subscription) do
    with {:end_period_reached?, :lt} <-
           {:end_period_reached?, DateTime.compare(Timex.now(), subscription.current_period_end)},
         {:ok, stripe_subscription} <-
           StripeApi.update_subscription(subscription.stripe_id, %{cancel_at_period_end: false}),
         {:ok, updated_subscription} <-
           sync_with_stripe_subscription(stripe_subscription, subscription) do
      {:ok, updated_subscription |> Repo.preload([plan: [:product]], force: true)}
    else
      {:end_period_reached?, _} ->
        {:end_period_reached_error,
         "Cancelled subscription has already reached the end period at #{
           subscription.current_period_end
         }"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def create_subscription_db(
        %Stripe.Subscription{
          id: stripe_id,
          current_period_end: current_period_end,
          cancel_at_period_end: cancel_at_period_end,
          status: status
        },
        user,
        plan
      ) do
    %__MODULE__{}
    |> changeset(%{
      stripe_id: stripe_id,
      user_id: user.id,
      plan_id: plan.id,
      current_period_end: DateTime.from_unix!(current_period_end),
      cancel_at_period_end: cancel_at_period_end,
      status: status
    })
    |> Repo.insert(on_conflict: :nothing)
  end

  def update_subscription_db(subscription, params) do
    subscription
    |> changeset(params)
    |> Repo.update()
  end

  def sync_all() do
    __MODULE__
    |> Repo.all()
    |> Enum.each(&sync_with_stripe_subscription/1)
  end

  def sync_with_stripe_subscription(%__MODULE__{stripe_id: stripe_id} = subscription) do
    with {:ok,
          %Stripe.Subscription{
            current_period_end: current_period_end,
            cancel_at_period_end: cancel_at_period_end,
            status: status,
            plan: %Stripe.Plan{id: stripe_plan_id}
          }} <- StripeApi.retrieve_subscription(stripe_id),
         {:plan_not_exist?, %Plan{id: plan_id}} <-
           {:plan_not_exist?, Plan.by_stripe_id(stripe_plan_id)} do
      update_subscription_db(subscription, %{
        current_period_end: DateTime.from_unix!(current_period_end),
        cancel_at_period_end: cancel_at_period_end,
        status: status,
        plan_id: plan_id
      })
    else
      {:plan_not_exist?, nil} ->
        Logger.error(
          "Error while syncing subscription: #{subscription.stripe_id}, reason: plan does not exist}"
        )

      {:error, reason} ->
        Logger.error(
          "Error while syncing subscription: #{subscription.stripe_id}, reason: #{inspect(reason)}"
        )
    end
  end

  def sync_with_stripe_subscription(_), do: :ok

  def sync_with_stripe_subscription(
        %Stripe.Subscription{
          current_period_end: current_period_end,
          cancel_at_period_end: cancel_at_period_end,
          status: status,
          plan: %Stripe.Plan{id: stripe_plan_id}
        },
        db_subscription
      ) do
    plan_id =
      case Plan.by_stripe_id(stripe_plan_id) do
        %Plan{id: plan_id} -> plan_id
        nil -> db_subscription.plan_id
      end

    update_subscription_db(db_subscription, %{
      current_period_end: DateTime.from_unix!(current_period_end),
      cancel_at_period_end: cancel_at_period_end,
      status: status,
      plan_id: plan_id
    })
  end

  @doc """
  List all active user subscriptions with plans and products.
  """
  def user_subscriptions(user) do
    user
    |> user_subscriptions_query()
    |> active_subscriptions_query()
    |> join_plan_and_product_query()
    |> Repo.all()
  end

  @doc """
  List active subcriptions' product ids
  """
  def user_subscriptions_product_ids(user) do
    user
    |> user_subscriptions_query()
    |> active_subscriptions_query()
    |> select_product_id_query()
    |> Repo.all()
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
  Return list of tuples
    * coupon_code
    * count of subscriptions created with coupon code
  """
  def subscriptions_count_by_coupon do
    {:ok, all_subscriptions} = Stripe.Subscription.list()

    all_subscriptions.data
    |> Enum.group_by(fn s -> s.metadata |> Map.get("coupon_id") end)
    |> Enum.reject(fn {coupon_id, _} -> is_nil(coupon_id) end)
    |> Enum.map(fn {coupon_id, subscriptions} -> {coupon_id, length(subscriptions)} end)
  end

  @doc """
  How much historical days a subscription plan can access.
  """
  def historical_data_in_days(%__MODULE__{plan: plan}, query, product) do
    plan
    |> Plan.plan_atom_name()
    |> AccessChecker.historical_data_in_days(query, product)
  end

  def realtime_data_cut_off_in_days(%__MODULE__{plan: plan}, query, product) do
    plan
    |> Plan.plan_atom_name()
    |> AccessChecker.realtime_data_cut_off_in_days(query, product)
  end

  @doc ~s"""
  Check if a query full access is given only to users with a plan higher than free.
  A query can be restricted but still accessible by not-paid users or users with
  lower plans. In this case historical and/or realtime data access can be cut off
  """
  defdelegate is_restricted?(query), to: AccessChecker

  def plan_name(subscription), do: subscription.plan.name

  # Private functions

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

  defp create_stripe_subscription(user, plan, nil) do
    subscription = %{
      customer: user.stripe_customer_id,
      items: [%{plan: plan.stripe_id}]
    }

    user
    |> san_balance()
    |> percent_discount()
    |> update_subscription_with_coupon(subscription)
    |> case do
      {:ok, subscription} ->
        StripeApi.create_subscription(subscription)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_stripe_subscription(user, plan, coupon) when not is_nil(coupon) do
    with {:ok, stripe_coupon} <- StripeApi.retrieve_coupon(coupon) do
      %{
        customer: user.stripe_customer_id,
        items: [%{plan: plan.stripe_id}]
      }
      |> modify_subscription_by_coupon(stripe_coupon)
      |> StripeApi.create_subscription()
    end
  end

  defp modify_subscription_by_coupon(subscription, %Stripe.Coupon{
         percent_off: percent_off,
         id: id
       })
       when percent_off == 100 do
    subscription
    |> Map.put(:trial_period_days, @free_trial_days_for_coupons)
    |> Map.put(:metadata, %{coupon_id: id})
  end

  defp modify_subscription_by_coupon(subscription, %Stripe.Coupon{id: coupon_id}) do
    Map.put(subscription, :coupon, coupon_id)
  end

  defp update_subscription_with_coupon(nil, subscription), do: {:ok, subscription}

  defp update_subscription_with_coupon(percent_off, subscription) when is_integer(percent_off) do
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

  defp user_subscriptions_query(user) do
    from(s in __MODULE__,
      where: s.user_id == ^user.id,
      order_by: [desc: s.id]
    )
  end

  defp active_subscriptions_query(query) do
    from(s in query, where: s.status != "canceled")
  end

  defp join_plan_and_product_query(query) do
    from(
      s in query,
      join: p in assoc(s, :plan),
      join: pr in assoc(p, :product),
      preload: [plan: {p, product: pr}]
    )
  end

  defp select_product_id_query(query) do
    from(s in query, join: p in assoc(s, :plan), select: p.product_id)
  end

  defp last_subscription_for_product_query(query, product_id) do
    from(s in query,
      where: s.plan_id in fragment("select id from plans where product_id = ?", ^product_id),
      limit: 1
    )
  end

  defp san_balance(%User{} = user) do
    case User.san_balance(user) do
      {:ok, %Decimal{} = balance} -> balance |> Decimal.to_float()
      _ -> 0
    end
  end
end
