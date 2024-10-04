defmodule Sanbase.StripeApi do
  @moduledoc """
  Module wrapping communication with Stripe.
  """

  alias Sanbase.Billing
  alias Sanbase.Billing.{Product, Plan}
  alias Sanbase.Accounts.User

  @type subscription_item :: %{plan: String.t()}
  @type subscription :: %{
          optional(:coupon) => String.t(),
          customer: String.t(),
          items: list(subscription_item)
        }

  def create_product(%Product{name: name}) do
    Stripe.Product.create(%{name: name, type: "service"})
  end

  def create_plan(%Plan{
        name: name,
        currency: currency,
        amount: amount,
        interval: interval,
        product: %Product{stripe_id: product_stripe_id}
      }) do
    Stripe.Plan.create(%{
      nickname: name,
      currency: currency,
      amount: amount,
      interval: interval,
      product: product_stripe_id
    })
  end

  @spec create_customer_with_card(%User{}, nil | String.t()) ::
          {:ok, Stripe.Customer.t()} | {:error, Stripe.Error.t()}
  def create_customer_with_card(%User{} = user, nil) do
    Stripe.Customer.create(%{
      description: user.username,
      email: user.email
    })
  end

  def create_customer_with_card(%User{} = user, card_token) do
    Stripe.Customer.create(%{
      description: user.username,
      email: user.email,
      source: card_token
    })
  end

  @spec update_customer_card(%User{stripe_customer_id: binary()}, String.t()) ::
          {:ok, Stripe.Customer.t()} | {:error, Stripe.Error.t()}
  def update_customer_card(%User{stripe_customer_id: stripe_customer_id}, card_token)
      when is_binary(stripe_customer_id) do
    Stripe.Customer.update(stripe_customer_id, %{source: card_token})
  end

  @spec update_customer(String.t(), map()) ::
          {:ok, Stripe.Customer.t()} | {:error, Stripe.Error.t()}
  def update_customer(stripe_customer_id, params) when is_binary(stripe_customer_id) do
    Stripe.Customer.update(stripe_customer_id, params)
  end

  def fetch_default_card(%User{stripe_customer_id: stripe_customer_id})
      when is_binary(stripe_customer_id) do
    Stripe.Customer.retrieve(stripe_customer_id, expand: ["default_source"])
  end

  def fetch_default_card(_), do: {:error, "Customer has no default card"}

  def delete_default_card(%User{stripe_customer_id: stripe_customer_id})
      when is_binary(stripe_customer_id) do
    with {:ok, customer} <- Stripe.Customer.retrieve(stripe_customer_id),
         {:ok, _} <- delete_card(customer) do
      :ok
    end
  end

  def delete_default_card(_), do: {:error, "Customer has no default card"}

  # This function is used to delete the default card of a customer
  # First try to delete default_source, if it fails, try to delete default_payment_method
  # Old customers have default_source, new customers have default_payment_method - that is due to changes in the way payments are handled.
  def delete_card(customer) do
    cond do
      is_binary(customer.default_source) ->
        Stripe.Card.delete(customer.id, customer.default_source)

      is_binary(customer.invoice_settings.default_payment_method) ->
        Stripe.PaymentMethod.detach(%{
          payment_method: customer.invoice_settings.default_payment_method
        })

      true ->
        {:error, "Customer has no default card"}
    end
  end

  def retrieve_payment_method(payment_method_id) do
    Stripe.PaymentMethod.retrieve(payment_method_id)
  end

  def retrieve_customer(%User{stripe_customer_id: stripe_customer_id}) do
    Stripe.Customer.retrieve(stripe_customer_id)
  end

  def attach_payment_method_to_customer(user, payment_method_id) do
    # Step 1: Attach payment method to the customer
    {:ok, user} = Billing.create_or_update_stripe_customer(user)

    {:ok, pm} =
      Stripe.PaymentMethod.attach(payment_method_id, %{customer: user.stripe_customer_id})

    # Step 2: Set this payment method as default for the customer
    update_params = %{
      invoice_settings: %{default_payment_method: pm.id}
    }

    with {:ok, _} <- update_customer(user.stripe_customer_id, update_params) do
      remove_duplicate_payment_methods(pm.id, user.stripe_customer_id)

      {:ok, user}
    end
  end

  @doc """
  Remove duplicate payment methods with the same fingerprint.
  """
  @spec remove_duplicate_payment_methods(String.t(), String.t()) :: :ok | any()
  def remove_duplicate_payment_methods(payment_method_id, customer_id) do
    with {:ok, payment_method} <- Stripe.PaymentMethod.retrieve(payment_method_id),
         {:ok, %Stripe.List{data: payment_methods}} <-
           Stripe.PaymentMethod.list(customer: customer_id),
         fingerprint <- payment_method.card.fingerprint do
      payment_methods
      |> Enum.filter(fn pm ->
        pm.card.fingerprint == fingerprint && pm.id != payment_method_id
      end)
      |> Enum.each(fn pm ->
        Stripe.PaymentMethod.detach(pm.id)
      end)
    end
  end

  # Detach payment method if it exists
  def maybe_detach_payment_method(stripe_customer_id) do
    with {:ok, customer} <- Stripe.Customer.retrieve(stripe_customer_id),
         default_payment_method when is_binary(default_payment_method) <-
           customer.invoice_settings.default_payment_method,
         {:ok, %Stripe.PaymentMethod{}} <-
           Stripe.PaymentMethod.detach(%{
             payment_method: default_payment_method
           }) do
      :ok
    end
  end

  # Stripe docs: https://stripe.com/docs/payments/setupintents/lifecycle
  # Stripe API: https://stripe.com/docs/api/setup_intents
  def create_setup_intent(%User{} = user) do
    case Billing.create_or_update_stripe_customer(user) do
      {:ok, user} ->
        Stripe.SetupIntent.create(%{
          customer: user.stripe_customer_id,
          usage: "off_session",
          automatic_payment_methods: %{
            enabled: true
          }
        })

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec create_subscription(subscription) ::
          {:ok, %Stripe.Subscription{}} | {:error, %Stripe.Error{}}
  def create_subscription(%{customer: _customer, items: _items} = subscription) do
    Stripe.Subscription.create(subscription, expand: ["latest_invoice.payment_intent"])
  end

  def update_subscription(stripe_id, params) do
    Stripe.Subscription.update(stripe_id, params, expand: ["latest_invoice.payment_intent"])
  end

  def cancel_subscription_at_period_end(stripe_id) do
    stripe_id
    |> update_subscription(%{cancel_at_period_end: true})
  end

  def cancel_subscription_immediately(stripe_id) do
    Stripe.Subscription.cancel(stripe_id)
  end

  def retrieve_subscription(stripe_id) do
    Stripe.Subscription.retrieve(stripe_id, expand: ["latest_invoice.payment_intent"])
  end

  def list_subscriptions(params, kw_list \\ []) do
    Stripe.Subscription.list(params, kw_list)
  end

  def upgrade_downgrade(db_subscription, plan) do
    with {:ok, params} <- get_upgrade_downgrade_subscription_params(db_subscription, plan),
         # Remove coupon for free basic API subscription
         {:ok, params} <- maybe_remove_coupon(params, db_subscription, plan),
         {:ok, stripe_subscription} <- update_subscription(db_subscription.stripe_id, params) do
      {:ok, stripe_subscription}
    end
  end

  def get_upgrade_downgrade_subscription_params(db_subscription, plan) do
    with {:ok, item_id} <- get_subscription_first_item_id(db_subscription.stripe_id) do
      params = %{items: [%{id: item_id, plan: plan.stripe_id}]}
      {:ok, params}
    end
  end

  def create_coupon(%{percent_off: percent_off, duration: duration}) do
    Stripe.Coupon.create(%{percent_off: percent_off, duration: duration})
  end

  def create_promo_coupon(promo_args) do
    Stripe.Coupon.create(promo_args)
  end

  def retrieve_coupon(coupon_id) do
    Stripe.Coupon.retrieve(coupon_id)
  end

  def list_payments(%User{stripe_customer_id: stripe_customer_id})
      when is_binary(stripe_customer_id) do
    Stripe.Charge.list(%{customer: stripe_customer_id})
  end

  def list_payments(_) do
    {:ok, []}
  end

  def upcoming_invoice(stripe_id) do
    Stripe.Invoice.upcoming(%{subscription: stripe_id})
  end

  def list_invoices(params, kw_list \\ []) do
    Stripe.Invoice.list(params, kw_list)
  end

  def list_charges(params, kw_list \\ []) do
    Stripe.Charge.list(params, kw_list)
  end

  def add_credit(customer_id, amount, trx_id) do
    Stripe.CustomerBalanceTransaction.create(customer_id, %{
      amount: amount,
      currency: "USD",
      description: "https://etherscan.io/tx/#{trx_id}"
    })
  end

  # Helpers

  defp maybe_remove_coupon(params, db_subscription, _plan) do
    with {:ok, stripe_subscription} <- retrieve_subscription(db_subscription.stripe_id) do
      percent_off =
        get_in(stripe_subscription, [
          Access.key!(:discount),
          Access.key!(:coupon),
          Access.key!(:percent_off)
        ])

      is_basic_plan? = fn plan_id ->
        plan_id in Sanbase.Billing.Subscription.ProPlus.basic_api_plans()
      end

      if is_basic_plan?.(db_subscription.plan_id) and percent_off == 100.0 do
        {:ok, Map.put(params, :coupon, nil)}
      else
        {:ok, params}
      end
    end
  end

  defp get_subscription_first_item_id(stripe_id) do
    stripe_id
    |> retrieve_subscription()
    |> case do
      {:ok, subscription} ->
        item_id =
          subscription.items.data
          |> hd()
          |> Map.get(:id)

        {:ok, item_id}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def delete_customer(user) do
    Stripe.Customer.delete(user.stripe_customer_id)
    User.update_field(user, :stripe_customer_id, nil)
  end
end

defmodule Sanbase.StripeApi.Webhook do
  def construct_event(body, signature, webhook_secret) do
    Stripe.Webhook.construct_event(body, signature, webhook_secret)
  end
end
