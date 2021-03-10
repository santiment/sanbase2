defmodule Sanbase.Billing do
  @moduledoc ~s"""
  Context module for all billing functionality
  """

  import Ecto.Query

  alias Sanbase.Repo
  alias Sanbase.Billing.{Product, Plan, Subscription}
  alias Sanbase.Billing.Subscription.{LiquiditySubscription, SignUpTrial}
  alias Sanbase.Accounts.User
  alias Sanbase.StripeApi

  # Subscription API
  defdelegate subscribe(user, plan, card, coupon), to: Subscription
  defdelegate update_subscription(subscription, plan), to: Subscription
  defdelegate cancel_subscription(subscription), to: Subscription
  defdelegate renew_cancelled_subscription(subscription), to: Subscription

  defdelegate sync_stripe_subscriptions, to: Subscription
  defdelegate remove_duplicate_subscriptions, to: Subscription

  # SignUpTrial
  defdelegate create_trial_subscription(user_id), to: SignUpTrial
  defdelegate cancel_about_to_expire_trials, to: SignUpTrial
  defdelegate update_finished_trials, to: SignUpTrial
  defdelegate send_email_on_trial_day, to: SignUpTrial

  # LiquiditySubscription
  defdelegate create_liquidity_subscription(user_id), to: LiquiditySubscription
  defdelegate remove_liquidity_subscription(liquidity_subscription), to: LiquiditySubscription
  defdelegate list_liquidity_subscriptions, to: LiquiditySubscription
  defdelegate eligible_for_liquidity_subscription?(user_id), to: LiquiditySubscription
  defdelegate user_has_active_sanbase_subscriptions?(user_id), to: LiquiditySubscription
  defdelegate sync_liquidity_subscriptions_staked_users, to: LiquiditySubscription
  defdelegate maybe_create_liquidity_subscriptions_staked_users, to: LiquiditySubscription
  defdelegate maybe_remove_liquidity_subscriptions_staked_users, to: LiquiditySubscription

  def list_products(), do: Repo.all(Product)

  def list_plans() do
    from(p in Plan, preload: [:product])
    |> Repo.all()
  end

  @doc ~s"""
  Sync the locally defined Products and Plans with stripe.

  This acction assings a `stripe_id` to every product and plan without which
  no subscription can succeed.

  In order to create the Products and Plans locally, the seed
  `priv/repo/seed_plans_and_products.exs` must be executed.
  """
  @spec sync_products_with_stripe() :: :ok | {:error, %Stripe.Error{}}
  def sync_products_with_stripe() do
    with :ok <- run_sync(list_products(), &Product.maybe_create_product_in_stripe/1),
         :ok <- run_sync(list_plans(), &Plan.maybe_create_plan_in_stripe/1) do
      :ok
    else
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  If user has enough SAN staked and has no active Sanbase subscription - create one
  Or if user is not yet registered - create a 14 day trial
  """
  @spec maybe_create_liquidity_or_trial_subscription(non_neg_integer()) ::
          {:ok, %Subscription{}} | {:ok, %SignUpTrial{}} | {:error, any()}
  def maybe_create_liquidity_or_trial_subscription(user_id) do
    case eligible_for_liquidity_subscription?(user_id) do
      true -> create_liquidity_subscription(user_id)
      false -> create_trial_subscription(user_id)
    end
  end

  # Private functions

  # Return :ok if all function calls over the list return {:ok, _}
  # Return the error otherwise
  defp run_sync(list, function) when is_function(function, 1) do
    Enum.map(list, function)
    |> Enum.find(:ok, fn
      {:ok, _} -> false
      {:error, _} -> true
    end)
  end

  @spec create_or_update_stripe_customer(%User{}, String.t() | nil) ::
          {:ok, %User{}} | {:error, %Stripe.Error{}}
  def create_or_update_stripe_customer(user, card_token \\ nil)

  def create_or_update_stripe_customer(%User{stripe_customer_id: nil} = user, card_token) do
    with {:ok, stripe_customer} <- StripeApi.create_customer(user, card_token) do
      User.update_field(user, :stripe_customer_id, stripe_customer.id)
    end
  end

  def create_or_update_stripe_customer(%User{stripe_customer_id: stripe_id} = user, nil)
      when is_binary(stripe_id) do
    {:ok, user}
  end

  def create_or_update_stripe_customer(%User{stripe_customer_id: stripe_id} = user, card_token)
      when is_binary(stripe_id) do
    with {:ok, _} <- StripeApi.update_customer(user, card_token) do
      {:ok, user}
    end
  end
end
