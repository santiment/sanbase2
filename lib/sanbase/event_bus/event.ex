defmodule Sanbase.EventBus.Event do
  require Sanbase.Utils.Config, as: Config

  @invalid_event_handler Config.get(:invalid_event_handler, __MODULE__)

  ## User Events
  def valid?(%{event_type: :update_username, user_id: id, old_username: old, new_username: new}),
    do: valid_integer_id?(id) and valid_string_field_change?(old, new)

  def valid?(%{event_type: :update_email, user_id: id, old_email: old, new_email: new}),
    do: valid_integer_id?(id) and valid_string_field_change?(old, new) and is_binary(new)

  def valid?(%{event_type: :update_email_candidate, user_id: id, email_candidate: email}),
    do: valid_integer_id?(id) and is_binary(email)

  def valid?(%{event_type: :register_user, user_id: id, login_origin: _origin}),
    do: valid_integer_id?(id)

  ## Alert Events
  def valid?(%{event_type: :create_alert, user_id: user_id, alert_id: alert_id}),
    do: valid_integer_id?(user_id) and valid_integer_id?(alert_id)

  def valid?(%{event_type: :alert_triggered, user_id: user_id, alert_id: alert_id}),
    do: valid_integer_id?(user_id) and valid_integer_id?(alert_id)

  ## Watchlist Events
  def valid?(%{event_type: :create_watchlist, user_id: user_id, watchlist_id: watchlist_id}),
    do: valid_integer_id?(user_id) and valid_integer_id?(watchlist_id)

  def valid?(%{event_type: :delete_watchlist, user_id: user_id, watchlist_id: watchlist_id}),
    do: valid_integer_id?(user_id) and valid_integer_id?(watchlist_id)

  ## Billing Events
  def valid?(%{
        event_type: :create_stripe_customer,
        user_id: user_id,
        stripe_customer_id: customer_id,
        card_token: card_token
      }),
      do:
        valid_integer_id?(user_id) and valid_string_id?(customer_id) and
          (is_nil(card_token) or is_binary(card_token))

  def valid?(%{
        event_type: event_type,
        user_id: user_id,
        stripe_customer_id: customer_id,
        card_token: card_token
      })
      when event_type in [:create_stripe_customer, :update_stripe_customer],
      do:
        valid_integer_id?(user_id) and valid_string_id?(customer_id) and
          (is_nil(card_token) or is_binary(card_token))

  def valid?(%{
        event_type: event_type,
        subscription_id: subscription_id,
        user_id: user_id,
        stripe_subscription_id: stripe_subscription_id
      })
      when event_type in [:create_subscription, :update_subscription],
      do:
        valid_integer_id?(subscription_id) and valid_integer_id?(user_id) and
          valid_string_id?(stripe_subscription_id)

  ## Payment Events
  def valid?(%{event_type: :payment_success, user_id: user_id, stripe_id: stripe_id}),
    do: valid_integer_id?(user_id) and valid_string_id?(stripe_id)

  def valid?(%{event_type: :payment_fail, user_id: user_id, stripe_id: stripe_id}),
    do: valid_integer_id?(user_id) and valid_string_id?(stripe_id)

  def valid?(%{
        event_type: :new_subscription,
        user_id: user_id,
        stripe_id: stripe_id,
        plan: plan,
        product: product
      }) do
    valid_integer_id?(user_id) and valid_string_id?(stripe_id) and
      plan in Sanbase.Billing.Plan.plans() and
      product in Sanbase.Billing.Product.product_atom_names()
  end

  def valid?(%{
        event_type: :cancel_subscription,
        user_id: user_id,
        stripe_id: stripe_id,
        plan: plan,
        product: product
      }) do
    valid_integer_id?(user_id) and valid_string_id?(stripe_id) and
      plan in Sanbase.Billing.Plan.plans() and
      product in Sanbase.Billing.Product.product_atom_names()
  end

  def valid?(%{
        event_type: :apply_subscription_promocode,
        user_id: user_id,
        stripe_id: stripe_id,
        plan: plan,
        product: product,
        promo_code: promo_code
      }) do
    valid_integer_id?(user_id) and valid_string_id?(stripe_id) and is_binary(promo_code) and
      plan in Sanbase.Billing.Plan.plans() and
      product in Sanbase.Billing.Product.product_atom_names()
  end

  def valid?(%{} = event) do
    # For testing purposes. If an event is marked as valid it will be passed. This is
    # used so a custom testing subscriber can be attached to a topic without
    # poluting the event validation here
    Map.get(event, :__internal_valid_event__) == true
  end

  # Private functions

  defp valid_integer_id?(id), do: is_integer(id) and id > 0
  defp valid_string_id?(id), do: is_binary(id) and id != ""
  defp valid_string_field_change?(old, new), do: is_binary(old) and is_binary(new) and old != new
end
