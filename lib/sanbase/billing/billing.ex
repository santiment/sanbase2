defmodule Sanbase.Billing do
  @moduledoc ~s"""
  Context module for all billing functionality
  """

  import Ecto.Query
  import Sanbase.Billing.EventEmitter, only: [emit_event: 3]

  alias Sanbase.Repo
  alias Sanbase.Billing.{Product, Plan, Subscription}
  alias Sanbase.Billing.Plan.Bundle.Catalog
  alias Sanbase.Billing.Plan.Bundle.ItemExpiry
  alias Sanbase.Billing.Plan.Bundle.Lifecycle
  alias Sanbase.Billing.Subscription.LiquiditySubscription
  alias Sanbase.Billing.Subscription.ProPlus
  alias Sanbase.Accounts.User
  alias Sanbase.StripeApi

  # Subscription API
  defdelegate subscribe(user, plan, card, coupon), to: Subscription
  defdelegate update_subscription(subscription, plan), to: Subscription
  defdelegate cancel_subscription_at_period_end(subscription), to: Subscription
  defdelegate renew_cancelled_subscription(subscription), to: Subscription
  defdelegate user_has_active_sanbase_subscriptions?(user_id), to: Subscription

  defdelegate sync_stripe_subscriptions, to: Subscription
  defdelegate remove_duplicate_subscriptions, to: Subscription

  # Bundle subscriptions
  defdelegate expire_bundle_subscription_items, to: ItemExpiry, as: :run

  defdelegate cancel_stale_replaced_subscriptions, to: Lifecycle

  # LiquiditySubscription
  defdelegate create_liquidity_subscription(user_id), to: LiquiditySubscription
  defdelegate remove_liquidity_subscription(liquidity_subscription), to: LiquiditySubscription
  defdelegate list_liquidity_subscriptions, to: LiquiditySubscription
  defdelegate eligible_for_liquidity_subscription?(user_id), to: LiquiditySubscription
  defdelegate sync_liquidity_subscriptions_staked_users, to: LiquiditySubscription
  defdelegate maybe_create_liquidity_subscriptions_staked_users, to: LiquiditySubscription
  defdelegate maybe_remove_liquidity_subscriptions_staked_users, to: LiquiditySubscription

  # ProPlus
  defdelegate create_free_basic_api, to: ProPlus
  defdelegate delete_free_basic_api, to: ProPlus

  def list_products(), do: Repo.all(Product)

  def list_plans() do
    from(p in Plan, preload: [:product])
    |> Repo.all()
  end

  def eligible_for_sanbase_trial?(user_id) do
    Subscription.all_user_subscriptions_for_product(user_id, Product.product_sanbase())
    |> Enum.empty?()
  end

  def eligible_for_sanbase_trial?(user_id, plan) do
    # Only PRO plans are eligible for trials
    plan.name == "PRO" and eligible_for_sanbase_trial?(user_id)
  end

  def eligible_for_api_trial?(user_id) do
    Subscription.all_user_subscriptions_for_product(user_id, Product.product_api())
    |> Enum.empty?()
  end

  @doc ~s"""
  Sync the locally defined Products, Plans, and bundle catalog prices with Stripe.

  Assigns a `stripe_id` to every product and plan without which no subscription
  can succeed, and creates missing Stripe Prices for sellable bundle catalog
  rows (`Bundle.Catalog.sync_with_stripe/0`).

  In order to create the Products and Plans locally, the seed
  `priv/repo/seed_plans_and_products.exs` must be executed. Bundle catalog rows
  are ensured by the catalog sync itself.

  Runs on `@reboot` via Quantum — the stage/prod entry point.
  Idempotent; rows with no amount (e.g. unpriced add-ons) are skipped.
  """
  @spec sync_products_with_stripe() :: :ok | {:error, term()}
  def sync_products_with_stripe() do
    with :ok <- run_sync(list_products(), &Product.maybe_create_product_in_stripe/1),
         :ok <- run_sync(list_plans(), &Plan.maybe_create_plan_in_stripe/1),
         :ok <- sync_bundle_catalog_ok() do
      :ok
    else
      {:error, error} -> {:error, error}
    end
  end

  @doc ~s"""
  Ensure local bundle catalog rows and create missing Stripe Products/Prices.

  Prefer this (or `sync_products_with_stripe/0`) remotely:

      Sanbase.Billing.sync_bundle_catalog_with_stripe()

  Also invoked from `sync_products_with_stripe/0` on `@reboot`.
  """
  @spec sync_bundle_catalog_with_stripe() :: {:ok, list()} | {:error, term()}
  def sync_bundle_catalog_with_stripe do
    Catalog.sync_with_stripe()
  end

  @doc ~s"""
  Move Institutional yearly to its 2026-09-10 price of $9,588.

  Run once, after the `Apply20260910PricingDecisions` migration:

      Sanbase.Billing.switch_institutional_yearly_price()

  ## Why this is not a migration

  A Stripe Plan is immutable, so changing the amount means creating a new Plan and
  pointing the row at it. A migration can only do half of that, and either half is a
  broken state a deploy can stop in: the row priced at $9,588 while its `stripe_id`
  still charges $9,500, or a purchasable row with no `stripe_id` at all.

  So the order here is create-then-switch. The new Stripe Plan is created from an
  in-memory copy carrying the new amount, and the row is only updated once that
  succeeded - if Stripe fails, nothing local changed and the old price keeps working.

  ## The old Stripe Plan is reported, not deleted

  Deactivating it is a Stripe-side action with no wrapper here, and doing it before the
  switch is confirmed would leave the live row pointing at a dead plan. The previous id
  comes back in the result so it can be archived in the dashboard afterwards. Nothing is
  subscribed to it - Institutional has never been on sale.

  Idempotent, and it checks rather than assumes: a row already at the new amount is left
  alone only once Stripe confirms its plan charges that amount too. A row seeded at
  $9,588 with no Stripe plan behind it, or one edited by hand, goes down the
  create-and-switch path like any other.
  """
  @spec switch_institutional_yearly_price() ::
          {:ok, :already_applied}
          | {:ok,
             %{
               plan_id: non_neg_integer(),
               stripe_id: String.t(),
               archive_in_stripe: String.t() | nil
             }}
          | {:error, term()}
  def switch_institutional_yearly_price do
    new_amount = 958_800

    case Repo.get_by(Plan, name: "INSTITUTIONAL", interval: "year") do
      nil ->
        {:error, "No INSTITUTIONAL yearly plan row exists."}

      %Plan{amount: ^new_amount, stripe_id: stripe_id} = plan when is_binary(stripe_id) ->
        # The local amount alone cannot tell a finished switch from a row seeded at the
        # new figure, or from one edited by hand - both would leave Stripe still charging
        # the old price while this reported success. So the Stripe Plan is asked.
        case Sanbase.StripeApi.plan_amount(stripe_id) do
          {:ok, ^new_amount} ->
            {:ok, :already_applied}

          {:ok, _other_amount} ->
            replace_institutional_yearly_price(plan, new_amount)

          {:error, error} ->
            {:error,
             "The local row is already at #{new_amount} but its Stripe plan #{stripe_id} " <>
               "could not be read, so it is not safe to call this done: #{inspect(error)}"}
        end

      %Plan{} = plan ->
        replace_institutional_yearly_price(plan, new_amount)
    end
  end

  defp replace_institutional_yearly_price(%Plan{} = plan, new_amount) do
    %Plan{} = plan = Repo.preload(plan, :product)
    previous_stripe_id = plan.stripe_id

    case Sanbase.StripeApi.create_plan(%Plan{plan | amount: new_amount}) do
      {:ok, stripe_plan} ->
        case Plan.update_plan(plan, %{amount: new_amount, stripe_id: stripe_plan.id}) do
          {:ok, updated} ->
            {:ok,
             %{
               plan_id: updated.id,
               stripe_id: updated.stripe_id,
               archive_in_stripe: previous_stripe_id
             }}

          {:error, error} ->
            # The Stripe Plan exists and nothing points at it. Reported rather than
            # cleaned up, because deleting it blind is the more dangerous of the two.
            {:error,
             "Created Stripe plan #{stripe_plan.id} but could not update the local row: " <>
               "#{inspect(error)}. Archive #{stripe_plan.id} in Stripe before retrying."}
        end

      {:error, error} ->
        {:error, "Could not create the replacement Stripe plan: #{inspect(error)}"}
    end
  end

  @doc """
  If user has enough SAN staked and has no active Sanbase subscription - create one
  """
  @spec maybe_create_liquidity_subscription(non_neg_integer()) ::
          {:ok, %Subscription{}} | {:error, any()} | false
  def maybe_create_liquidity_subscription(user_id) do
    eligible_for_liquidity_subscription?(user_id) && create_liquidity_subscription(user_id)
  end

  # Private functions

  defp sync_bundle_catalog_ok do
    case Catalog.sync_with_stripe() do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

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
    with {:ok, stripe_customer} = result <- StripeApi.create_customer_with_card(user, card_token) do
      emit_event(result, :create_stripe_customer, %{user: user, card_token: card_token})

      User.update_field(user, :stripe_customer_id, stripe_customer.id)
    end
  end

  def create_or_update_stripe_customer(%User{stripe_customer_id: stripe_id} = user, nil)
      when is_binary(stripe_id) do
    {:ok, user}
  end

  def create_or_update_stripe_customer(%User{stripe_customer_id: stripe_id} = user, card_token)
      when is_binary(stripe_id) do
    with {:ok, _} = result <- StripeApi.update_customer_card(user, card_token) do
      emit_event(result, :update_stripe_customer, %{user: user, card_token: card_token})

      {:ok, user}
    end
  end

  def get_sanbase_pro_user_ids() do
    sanbase_user_ids_mapset =
      Subscription.get_direct_sanbase_pro_user_ids()
      |> MapSet.new()

    linked_user_id_pairs = Sanbase.Accounts.LinkedUser.get_all_user_id_pairs()

    user_ids_inherited_sanbase_pro =
      Enum.reduce(linked_user_id_pairs, MapSet.new(), fn pair, acc ->
        {primary_user_id, secondary_user_id} = pair

        case primary_user_id in sanbase_user_ids_mapset do
          true -> MapSet.put(acc, secondary_user_id)
          false -> acc
        end
      end)

    result = MapSet.union(sanbase_user_ids_mapset, user_ids_inherited_sanbase_pro)
    {:ok, MapSet.to_list(result)}
  end
end
