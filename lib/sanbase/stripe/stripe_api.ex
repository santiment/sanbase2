defmodule Sanbase.StripeApi do
  @moduledoc """
  Module wrapping communication with Stripe.
  """

  alias Sanbase.Billing.{Product, Plan}
  alias Sanbase.Accounts.User

  @type subscription_item :: %{plan: String.t()}
  @type subscription :: %{
          optional(:coupon) => String.t(),
          customer: String.t(),
          items: list(subscription_item)
        }

  @spec create_customer(%User{}, nil | String.t()) ::
          {:ok, Stripe.Customer.t()} | {:error, Stripe.Error.t()}
  def create_customer(%User{} = user, nil) do
    Stripe.Customer.create(%{
      description: user.username,
      email: user.email
    })
  end

  def create_customer(%User{} = user, card_token) do
    Stripe.Customer.create(%{
      description: user.username,
      email: user.email,
      source: card_token
    })
  end

  @spec update_customer(%User{}, String.t()) ::
          {:ok, Stripe.Customer.t()} | {:error, Stripe.Error.t()}
  def update_customer(%User{stripe_customer_id: stripe_customer_id}, card_token)
      when is_binary(stripe_customer_id) do
    Stripe.Customer.update(stripe_customer_id, %{source: card_token})
  end

  def retrieve_customer(%User{stripe_customer_id: stripe_customer_id}) do
    Stripe.Customer.retrieve(stripe_customer_id)
  end

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

  @spec create_subscription(subscription) ::
          {:ok, %Stripe.Subscription{}} | {:error, %Stripe.Error{}}
  def create_subscription(%{customer: _customer, items: _items} = subscription) do
    Stripe.Subscription.create(subscription)
  end

  def update_subscription(stripe_id, params) do
    Stripe.Subscription.update(stripe_id, params)
  end

  def cancel_subscription(stripe_id) do
    stripe_id
    |> update_subscription(%{cancel_at_period_end: true})
  end

  def delete_subscription(stripe_id) do
    Stripe.Subscription.delete(stripe_id)
  end

  def update_subscription_item_by_id(db_subscription, plan) do
    # Note: StripeApi.update_subscription/2 will generate dialyzer error
    # because the spec is wrong.
    # More info here: https://github.com/code-corps/stripity_stripe/pull/499
    with {:ok, item_id} <- get_subscription_first_item_id(db_subscription.stripe_id),
         {:ok, stripe_subscription} <-
           update_subscription(db_subscription.stripe_id, %{
             items: [%{id: item_id, plan: plan.stripe_id}]
           }) do
      {:ok, stripe_subscription}
    end
  end

  def retrieve_subscription(stripe_id) do
    Stripe.Subscription.retrieve(stripe_id)
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

  def fetch_default_card(%User{stripe_customer_id: stripe_customer_id})
      when is_binary(stripe_customer_id) do
    Stripe.Customer.retrieve(stripe_customer_id, expand: ["default_source"])
  end

  def fetch_default_card(_), do: {:error, "Customer has no default card"}

  def delete_default_card(%User{stripe_customer_id: stripe_customer_id})
      when is_binary(stripe_customer_id) do
    with {:ok, customer} <- Stripe.Customer.retrieve(stripe_customer_id),
         {:ok, %Stripe.Card{}} <-
           Stripe.Card.delete(customer.default_source, %{customer: stripe_customer_id}) do
      :ok
    end
  end

  def delete_default_card(_), do: {:error, "Customer has no default card"}

  # Helpers

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
end
