defmodule Sanbase.Billing do
  @moduledoc ~s"""
  Context module for all billing functionality
  """

  import Ecto.Query
  import Sanbase.Billing.EventEmitter, only: [emit_event: 3]

  alias Sanbase.Repo
  alias Sanbase.Billing.{Product, Plan, Subscription}
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

  @doc ~s"""
  Return the user's current Sanbase plan name (e.g. "FREE", "PRO", "MAX").
  Wraps `Subscription.current_subscription/2` + `Subscription.plan_name/1` so
  callers do not need to import `Product` or `Subscription` directly.
  """
  @spec sanbase_plan_name(User.t() | non_neg_integer()) :: String.t()
  def sanbase_plan_name(user_or_id) do
    user_or_id
    |> Subscription.current_subscription(Product.product_sanbase())
    |> Subscription.plan_name()
  end

  @doc ~s"""
  Return the user's effective plan name across Sanbase and API products.
  When the Sanbase plan is "FREE", fall back to the API product's plan name.
  """
  @spec sanbase_or_api_plan_name(non_neg_integer()) :: String.t()
  def sanbase_or_api_plan_name(user_id) when is_integer(user_id) do
    case Subscription.current_subscription_plan(user_id, Product.product_sanbase()) do
      "FREE" -> Subscription.current_subscription_plan(user_id, Product.product_api())
      sanbase_plan -> sanbase_plan
    end
  end

  @doc ~s"""
  Return the user's current Sanbase subscription struct (or `nil`).
  """
  @spec sanbase_subscription(non_neg_integer()) :: Subscription.t() | nil
  def sanbase_subscription(user_id) when is_integer(user_id) do
    Subscription.get_user_subscription(user_id, Product.product_sanbase())
  end

  @doc ~s"""
  True if the user has a non-FREE plan on the given product.
  """
  @spec user_has_product_access?(User.t() | non_neg_integer(), non_neg_integer()) :: boolean()
  def user_has_product_access?(user_or_id, product_id) do
    case Subscription.current_subscription(user_or_id, product_id) do
      nil -> false
      %Subscription{} = subscription -> Subscription.plan_name(subscription) != "FREE"
    end
  end

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
  Sync the locally defined Products and Plans with stripe.

  This acction assigns a `stripe_id` to every product and plan without which
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
  """
  @spec maybe_create_liquidity_subscription(non_neg_integer()) ::
          {:ok, %Subscription{}} | {:error, any()} | false
  def maybe_create_liquidity_subscription(user_id) do
    eligible_for_liquidity_subscription?(user_id) && create_liquidity_subscription(user_id)
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

  @doc ~s"""
  Fetch the latest Stripe state for the user's subscription and sync the local
  record (used when the UI needs the freshest payment-intent client secret).
  Returns the same `{:ok, subscription}` shape `Subscription.by_id/1` does, or
  one of the tagged-tuple error shapes consumed by the resolver's error
  handler.
  """
  @spec refresh_subscription_payment_intent(User.t(), non_neg_integer()) ::
          {:ok, Subscription.t()} | {:subscription?, any()} | {:error, any()}
  def refresh_subscription_payment_intent(%User{id: user_id}, subscription_id) do
    with {_, %Subscription{user_id: ^user_id} = subscription} <-
           {:subscription?, Subscription.by_id(subscription_id)},
         {:ok, stripe_subscription} <- StripeApi.retrieve_subscription(subscription.stripe_id) do
      Subscription.sync_subscription_with_stripe(stripe_subscription, subscription)
    end
  end

  @doc "List the user's past Stripe charges, mapped to GraphQL-shaped maps."
  @spec list_payments(User.t()) :: {:ok, [map()]} | {:error, any()}
  def list_payments(%User{} = user) do
    case StripeApi.list_payments(user) do
      {:ok, []} -> {:ok, []}
      {:ok, %Stripe.List{data: payments}} -> {:ok, transform_payments(payments)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Retrieve a Stripe coupon and project it onto a GraphQL-shaped map."
  @spec retrieve_coupon(String.t()) :: {:ok, map()} | {:error, any()}
  def retrieve_coupon(coupon) do
    case StripeApi.retrieve_coupon(coupon) do
      {:ok,
       %Stripe.Coupon{
         valid: valid,
         id: id,
         name: name,
         percent_off: percent_off,
         amount_off: amount_off
       }} ->
        {:ok,
         %{
           is_valid: valid,
           id: id,
           name: name,
           percent_off: percent_off,
           amount_off: amount_off
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc ~s"""
  Upcoming invoice for the user's subscription. Returns a `{period_start,
  period_end, amount_due}` map, `{:error, message}`, or `:no_subscription` /
  `:not_billable` for invariant failures.
  """
  @spec upcoming_invoice(User.t(), non_neg_integer()) :: {:ok, map()} | {:error, any()} | atom()
  def upcoming_invoice(%User{id: user_id}, subscription_id) do
    with %Subscription{user_id: ^user_id} = subscription <- Subscription.by_id(subscription_id),
         true <- subscription.status in [:active, :trialing, :past_due],
         {:ok, %Stripe.Invoice{} = invoice} <- StripeApi.upcoming_invoice(subscription.stripe_id) do
      {:ok,
       %{
         period_start: DateTime.from_unix!(invoice.period_start),
         period_end: DateTime.from_unix!(invoice.period_end),
         amount_due: invoice.total
       }}
    end
  end

  @doc "Default payment instrument projected to a GraphQL-shaped map."
  @spec default_payment_instrument(User.t()) :: {:ok, map()} | {:card?, nil} | {:error, any()}
  def default_payment_instrument(%User{} = user) do
    with {:ok, customer} <- StripeApi.fetch_stripe_customer(user),
         {:card?, card} when not is_nil(card) <- {:card?, choose_default_card(customer)} do
      {:ok,
       %{
         last4: card.last4,
         dynamic_last4: card[:dynamic_last4],
         exp_year: card.exp_year,
         exp_month: card.exp_month,
         brand: card.brand,
         funding: card.funding
       }}
    end
  end

  @doc "Replace the user's default payment card with `card_token`."
  @spec update_default_payment_instrument(User.t(), String.t()) ::
          {:ok, true} | {:error, any()}
  def update_default_payment_instrument(%User{} = user, card_token) do
    if user.stripe_customer_id do
      StripeApi.maybe_detach_payment_method(user.stripe_customer_id)
    end

    case create_or_update_stripe_customer(user, card_token) do
      {:ok, _} -> {:ok, true}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Detach the user's default payment card from their Stripe customer."
  @spec delete_default_payment_instrument(User.t()) :: {:ok, true} | :error | {:error, any()}
  def delete_default_payment_instrument(%User{} = user) do
    case StripeApi.delete_default_card(user) do
      :ok -> {:ok, true}
      other -> other
    end
  end

  @doc "Create a Stripe SetupIntent and return its `client_secret`."
  @spec create_setup_intent(User.t()) :: {:ok, %{client_secret: String.t()}} | {:error, any()}
  def create_setup_intent(%User{} = user) do
    case StripeApi.create_setup_intent(user) do
      {:ok, setup_intent} -> {:ok, %{client_secret: setup_intent.client_secret}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Stripe customer balance (in SAN credits), expressed as a positive float."
  @spec san_credit_balance(User.t()) :: float()
  def san_credit_balance(%User{} = user) do
    with {:ok, customer} <- StripeApi.retrieve_customer(user),
         true <- customer.balance < 0 do
      -(customer.balance / 100)
    else
      _ -> 0.00
    end
  end

  defp transform_payments(payments) do
    Enum.map(payments, fn
      %Stripe.Charge{
        status: status,
        amount: amount,
        created: created,
        receipt_url: receipt_url,
        description: description
      } ->
        %{
          status: status,
          amount: amount,
          created_at: DateTime.from_unix!(created),
          receipt_url: receipt_url,
          description: description
        }
    end)
  end

  # default card can be either a card token or a payment method
  # they are stored in different places in the customer object
  defp choose_default_card(customer) do
    cond do
      # Check for default payment method first
      is_map(customer.invoice_settings) and customer.invoice_settings.default_payment_method ->
        pm_id = customer.invoice_settings.default_payment_method
        {:ok, pm} = StripeApi.retrieve_payment_method(pm_id)
        pm.card

      # Fall back to default source if it exists and is a card
      customer.default_source && is_struct(customer.default_source, Stripe.Card) ->
        Map.from_struct(customer.default_source)

      # Handle card source type
      customer.default_source && is_map(customer.default_source) &&
          Map.get(customer.default_source, :type) == "card" ->
        get_in(customer.default_source, [:card]) || customer.default_source

      true ->
        nil
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
