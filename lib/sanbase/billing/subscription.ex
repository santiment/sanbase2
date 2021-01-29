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
  alias Sanbase.Accounts.User
  alias Sanbase.Repo
  alias Sanbase.StripeApi

  require Logger

  @percent_discount_1000_san 20
  @generic_error_message """
  Current subscription attempt failed.
  Please, contact administrator of the site for more information.
  """
  @free_trial_plans Plan.Metadata.free_trial_plans()
  @sanbase_basic_plan_id 205

  schema "subscriptions" do
    field(:stripe_id, :string)
    field(:current_period_end, :utc_datetime)
    field(:cancel_at_period_end, :boolean, null: false, default: false)
    field(:status, SubscriptionStatusEnum)
    field(:trial_end, :utc_datetime)

    belongs_to(:user, User)
    belongs_to(:plan, Plan)

    timestamps()
  end

  def generic_error_message, do: @generic_error_message

  def changeset(%__MODULE__{} = subscription, attrs \\ %{}) do
    subscription
    |> cast(attrs, [
      :plan_id,
      :user_id,
      :stripe_id,
      :current_period_end,
      :trial_end,
      :cancel_at_period_end,
      :status,
      :inserted_at
    ])
    |> foreign_key_constraint(:plan_id, name: :subscriptions_plan_id_fkey)
  end

  def create(params) do
    %__MODULE__{}
    |> changeset(params)
    |> Repo.insert()
  end

  def by_id(id) do
    Repo.get(__MODULE__, id)
    |> Repo.preload(:plan)
  end

  def by_stripe_id(stripe_id) do
    Repo.get_by(__MODULE__, stripe_id: stripe_id)
    |> Repo.preload(:plan)
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
  @type string_or_nil :: String.t() | nil
  @spec subscribe(%User{}, %Plan{}, string_or_nil, string_or_nil) ::
          {:ok, %__MODULE__{}} | {atom(), String.t()}
  def subscribe(user, plan, card_token \\ nil, coupon \\ nil) do
    with {:ok, %User{stripe_customer_id: id} = user} when not is_nil(id) <-
           create_or_update_stripe_customer(user, card_token),
         {:ok, stripe_subscription} <- create_stripe_subscription(user, plan, coupon),
         {:ok, subscription} <- create_subscription_db(stripe_subscription, user, plan),
         {:ok, _} <- Sanbase.ApiCallLimit.update_user_plan(user) do
      {:ok, subscription |> Repo.preload([plan: [:product]], force: true)}
    end
  end

  @doc """
  Upgrade or Downgrade plan:

  - Updates subcription in Stripe with new plan.
  - Updates local subscription
  Stripe docs:   https://stripe.com/docs/billing/subscriptions/upgrading-downgrading#switching
  """
  def update_subscription(%__MODULE__{} = sub, plan) do
    # Note: StripeApi.update_subscription/2 will generate dialyzer error
    # because the spec is wrong.
    # More info here: https://github.com/code-corps/stripity_stripe/pull/499
    with {:ok, item_id} <- StripeApi.get_subscription_first_item_id(sub.stripe_id),
         {:ok, stripe_sub} <-
           StripeApi.update_subscription(sub.stripe_id, %{
             items: [%{id: item_id, plan: plan.stripe_id}]
           }),
         {:ok, updated_sub} <- sync_with_stripe_subscription(stripe_sub, sub),
         %__MODULE__{user: user} = updated_sub <-
           Repo.preload(updated_sub, [:user, plan: [:product]], force: true),
         {:ok, _} <- Sanbase.ApiCallLimit.update_user_plan(user) do
      {:ok, updated_sub}
    end
  end

  @doc """
  Cancel subscription:

  Cancellation means scheduling for cancellation.
  It updates the `cancel_at_period_end` field which will cancel the subscription
  at `current_period_end`. That allows user to use the subscription for the time
  left that he has already paid for.
  https://stripe.com/docs/billing/subscriptions/canceling-pausing#canceling
  """
  def cancel_subscription(%__MODULE__{stripe_id: stripe_id} = sub) when is_binary(stripe_id) do
    with {:ok, stripe_sub} <- StripeApi.cancel_subscription(stripe_id),
         {:ok, _canceled_sub} <- sync_with_stripe_subscription(stripe_sub, sub),
         %__MODULE__{user: user} <- Repo.preload(sub, [:user]),
         {:ok, _} <- Sanbase.ApiCallLimit.update_user_plan(user) do
      Sanbase.Billing.StripeEvent.send_cancel_event_to_discord(sub)

      {:ok,
       %{
         is_scheduled_for_cancellation: true,
         scheduled_for_cancellation_at: sub.current_period_end
       }}
    end
  end

  def cancel_subscription(_),
    do: {:error, "This type of automatically created subscription can't be cancelled"}

  @doc """
  Renew cancelled subscription if `current_period_end` is not reached.

  https://stripe.com/docs/billing/subscriptions/canceling-pausing#reactivating-canceled-subscriptions
  """
  def renew_cancelled_subscription(%__MODULE__{} = sub) do
    dt_comparison = DateTime.compare(Timex.now(), sub.current_period_end)

    with {_, :lt} <- {:end_period_reached?, dt_comparison},
         {:ok, stripe_sub} <-
           StripeApi.update_subscription(sub.stripe_id, %{cancel_at_period_end: false}),
         {:ok, updated_sub} <- sync_with_stripe_subscription(stripe_sub, sub),
         %__MODULE__{user: user} <- Repo.preload(updated_sub, [:user]),
         {:ok, _} <- Sanbase.ApiCallLimit.update_user_plan(user) do
      {:ok, Repo.preload(updated_sub, [plan: [:product]], force: true)}
    else
      {:end_period_reached?, _} ->
        {:end_period_reached_error,
         "Cancelled subscription has already reached the end period at #{sub.current_period_end}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def create_subscription_db(
        %Stripe.Subscription{
          id: stripe_id,
          current_period_end: current_period_end,
          cancel_at_period_end: cancel_at_period_end,
          status: status,
          created: created
        } = stripe_subscription,
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
      status: status,
      trial_end: calculate_trial_end(stripe_subscription),
      inserted_at: DateTime.from_unix!(created) |> DateTime.to_naive()
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

  def sync_with_stripe_subscription(%__MODULE__{stripe_id: stripe_id} = sub) do
    with {:ok, %Stripe.Subscription{} = stripe_sub} <- StripeApi.retrieve_subscription(stripe_id),
         {_, %Plan{} = plan} <- {:plan_exists?, Plan.by_stripe_id(stripe_sub.plan.id)} do
      args = %{
        current_period_end: DateTime.from_unix!(stripe_sub.current_period_end),
        cancel_at_period_end: stripe_sub.cancel_at_period_end,
        status: stripe_sub.status,
        plan_id: plan.id,
        trial_end: calculate_trial_end(stripe_sub),
        inserted_at: DateTime.from_unix!(stripe_sub.created) |> DateTime.to_naive()
      }

      update_subscription_db(sub, args)
    else
      {:plan_exists?, nil} ->
        Logger.error(
          "Error while syncing subscription: #{sub.stripe_id}. Reason: Plan does not exist."
        )

      {:error, reason} ->
        Logger.error(
          "Error while syncing subscription: #{sub.stripe_id}. Reason: #{inspect(reason)}"
        )
    end
  end

  def sync_with_stripe_subscription(_), do: :ok

  def sync_with_stripe_subscription(
        %Stripe.Subscription{} = stripe_sub,
        db_subscription
      ) do
    plan_id =
      case Plan.by_stripe_id(stripe_sub.plan.id) do
        %Plan{id: plan_id} -> plan_id
        nil -> db_subscription.plan_id
      end

    update_subscription_db(db_subscription, %{
      current_period_end: DateTime.from_unix!(stripe_sub.current_period_end),
      cancel_at_period_end: stripe_sub.cancel_at_period_end,
      status: stripe_sub.status,
      plan_id: plan_id,
      trial_end: calculate_trial_end(stripe_sub)
    })
  end

  @doc """
  List all active user subscriptions with plans and products.
  """
  def user_subscriptions(%User{id: user_id}) do
    user_id
    |> user_subscriptions_query()
    |> active_subscriptions_query()
    |> join_plan_and_product_query()
    |> Repo.all()
  end

  @doc """
  List active subcriptions' product ids
  """
  def user_subscriptions_product_ids(%User{id: user_id}) do
    user_id
    |> user_subscriptions_query()
    |> active_subscriptions_query()
    |> select_product_id_query()
    |> Repo.all()
  end

  @doc """
  Current subscription is the last active subscription for a product.
  """
  def current_subscription(%User{id: user_id}, product_id) do
    fetch_current_subscription(user_id, product_id)
  end

  def current_subscription(user_id, product_id) when is_integer(user_id) do
    fetch_current_subscription(user_id, product_id)
  end

  def plan_name(nil), do: :free
  def plan_name(%__MODULE__{plan: plan}), do: plan |> Plan.plan_atom_name()

  def create_or_update_stripe_customer(_, _card_token \\ nil)

  def create_or_update_stripe_customer(%User{stripe_customer_id: stripe_id} = user, card_token)
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

  def create_or_update_stripe_customer(%User{stripe_customer_id: stripe_id} = user, nil)
      when is_binary(stripe_id) do
    {:ok, user}
  end

  def create_or_update_stripe_customer(%User{stripe_customer_id: stripe_id} = user, card_token)
      when is_binary(stripe_id) do
    StripeApi.update_customer(user, card_token)
    |> case do
      {:ok, _} ->
        {:ok, user}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Cancel trialing subscriptions.
  * For Sanbase PRO cancel those:
   - about to expire (in 2 hours)
   - there is no payment instrument attached
  and send an email for finished trial.

  * For other plans - cancel regardless of card presense.
  """
  def cancel_about_to_expire_trials() do
    now = Timex.now()
    after_2_hours = Timex.shift(now, hours: 2)

    from(s in __MODULE__,
      where:
        s.status == "trialing" and
          s.trial_end >= ^now and s.trial_end <= ^after_2_hours
    )
    |> Repo.all()
    |> Enum.each(&maybe_send_email_and_delete_subscription/1)
  end

  def active_subscriptions_map() do
    from(s in __MODULE__, where: s.status == "active", preload: [plan: [:product]])
    |> Sanbase.Repo.all()
    |> Enum.map(fn s ->
      %{user_id: s.user_id, product: "#{s.plan.product.name}/#{s.plan.name}"}
    end)
    |> Enum.group_by(& &1.user_id)
    |> Enum.into(%{}, fn {user_id, products} ->
      {user_id, Enum.map(products, & &1.product) |> Enum.join(", ")}
    end)
  end

  # Private functions

  # Add 80% off Sanbase Basic subscription for first month
  defp create_stripe_subscription(user, %Plan{id: plan_id} = plan, _)
       when plan_id == @sanbase_basic_plan_id do
    with {:ok, coupon} <- StripeApi.create_coupon(%{percent_off: 80, duration: "once"}) do
      subscription_defaults(user, plan)
      |> update_subscription_with_coupon(coupon)
      |> StripeApi.create_subscription()
    end
  end

  # When user doesn't provide coupon - check if he has SAN staked
  defp create_stripe_subscription(user, plan, nil) do
    percent_off =
      user
      |> san_balance()
      |> percent_discount()

    subscription_defaults(user, plan)
    |> update_subscription_with_coupon(percent_off)
    |> case do
      {:ok, subscription} ->
        StripeApi.create_subscription(subscription)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # When user provided a coupon - use it
  defp create_stripe_subscription(user, plan, coupon) when not is_nil(coupon) do
    with {:ok, stripe_coupon} <- StripeApi.retrieve_coupon(coupon) do
      subscription_defaults(user, plan)
      |> update_subscription_with_coupon(stripe_coupon)
      |> StripeApi.create_subscription()
    end
  end

  defp subscription_defaults(user, plan) do
    %{
      customer: user.stripe_customer_id,
      items: [%{plan: plan.stripe_id}]
    }
  end

  defp update_subscription_with_coupon(subscription, %Stripe.Coupon{id: coupon_id}) do
    Map.put(subscription, :coupon, coupon_id)
  end

  defp update_subscription_with_coupon(subscription, percent_off) when is_integer(percent_off) do
    with {:ok, coupon} <-
           StripeApi.create_coupon(%{percent_off: percent_off, duration: "forever"}) do
      {:ok, Map.put(subscription, :coupon, coupon.id)}
    end
  end

  defp update_subscription_with_coupon(subscription, nil), do: {:ok, subscription}

  defp percent_discount(balance) when balance >= 1000, do: @percent_discount_1000_san
  defp percent_discount(_), do: nil

  defp user_subscriptions_query(user_id) do
    from(s in __MODULE__,
      where: s.user_id == ^user_id,
      order_by: [desc: s.id]
    )
  end

  defp active_subscriptions_query(query) do
    from(s in query,
      where: s.status == "active" or s.status == "trialing" or s.status == "past_due"
    )
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
      {:ok, balance} -> balance
      _ -> 0
    end
  end

  defp calculate_trial_end(%Stripe.Subscription{
         trial_end: trial_end,
         cancel_at: cancel_at,
         metadata: %{"current_promotion" => "devcon2019"}
       }) do
    format_trial_end(trial_end || cancel_at)
  end

  defp calculate_trial_end(%Stripe.Subscription{
         trial_end: trial_end,
         cancel_at: cancel_at,
         created: created
       })
       when not is_nil(cancel_at) and not is_nil(created) do
    # set trial_end if subscription is set to end 14 days after it is created
    if ((cancel_at - created) / (3600 * 24)) |> Float.round() == 14 do
      format_trial_end(trial_end || cancel_at)
    else
      format_trial_end(trial_end)
    end
  end

  defp calculate_trial_end(%Stripe.Subscription{trial_end: trial_end}) do
    format_trial_end(trial_end)
  end

  # Send email and delete subscription if user plan is one of our free trial plans
  defp maybe_send_email_and_delete_subscription(
         %__MODULE__{
           user_id: user_id,
           stripe_id: stripe_id,
           plan_id: plan_id
         } = subscription
       )
       when plan_id in @free_trial_plans do
    Logger.info("Deleting subscription with id: #{stripe_id} for user: #{user_id}")

    StripeApi.delete_subscription(stripe_id)

    __MODULE__.SignUpTrial.maybe_send_trial_finished_email(subscription)
  end

  defp maybe_send_email_and_delete_subscription(%__MODULE__{stripe_id: stripe_id}) do
    Logger.info("Deleting subscription with id: #{stripe_id}")

    StripeApi.delete_subscription(stripe_id)
  end

  defp fetch_current_subscription(user_id, product_id) do
    user_id
    |> user_subscriptions_query()
    |> active_subscriptions_query()
    |> last_subscription_for_product_query(product_id)
    |> preload_query(plan: [:product])
    |> Repo.one()
  end

  defp preload_query(query, preloads) do
    from(s in query, preload: ^preloads)
  end

  defp format_trial_end(nil), do: nil
  defp format_trial_end(trial_end), do: DateTime.from_unix!(trial_end)
end
