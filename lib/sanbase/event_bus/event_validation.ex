defmodule Sanbase.EventBus.EventValidation do
  @moduledoc """
  When Sanbase.EventBus.notify/1 is called, the event is emitted only if it
  passes the validation in this module. Every event_type must have a function
  header definition that pattern matches on it and validates its fields
  """

  #############################################################################
  ## Accounts Events
  #############################################################################
  def valid?(%{event_type: :update_username, user_id: id, old_username: old, new_username: new}),
    do: valid_integer_id?(id) and valid_maybe_nil_string_field_change?(old, new)

  def valid?(%{event_type: :update_name, user_id: id, old_name: old, new_name: new}),
    do: valid_integer_id?(id) and valid_maybe_nil_string_field_change?(old, new)

  def valid?(%{event_type: :update_email, user_id: id, old_email: old, new_email: new}),
    do: valid_integer_id?(id) and valid_maybe_nil_string_field_change?(old, new)

  def valid?(%{event_type: :update_email_candidate, user_id: id, email_candidate: email}),
    do: valid_integer_id?(id) and is_binary(email)

  def valid?(%{event_type: :register_user, user_id: id, login_origin: login_origin}),
    do: valid_integer_id?(id) and (is_atom(login_origin) or is_binary(login_origin))

  def valid?(%{event_type: event_type, user_id: user_id, follower_id: follower_id})
      when event_type in [:follow_user, :unfollow_user] do
    valid_integer_id?(user_id) and valid_integer_id?(follower_id)
  end

  def valid?(%{event_type: :login_user, user_id: id, login_origin: login_origin}),
    do: valid_integer_id?(id) and (is_atom(login_origin) or is_binary(login_origin))

  def valid?(%{event_type: :send_email_login_link, user_id: id}),
    do: valid_integer_id?(id)

  def valid?(%{event_type: :create_user, user_id: id}), do: valid_integer_id?(id)

  #############################################################################
  ## Alert Events
  #############################################################################
  def valid?(%{event_type: event_type, user_id: user_id, alert_id: alert_id})
      when event_type in [:create_alert, :delete_alert],
      do: valid_integer_id?(user_id) and valid_integer_id?(alert_id)

  def valid?(%{event_type: :alert_triggered, user_id: user_id, alert_id: alert_id}),
    do: valid_integer_id?(user_id) and valid_integer_id?(alert_id)

  #############################################################################
  ## Comments Events
  #############################################################################
  def valid?(%{
        event_type: :create_comment,
        user_id: user_id,
        comment_id: comment_id,
        entity: entity
      }),
      do: valid_integer_id?(user_id) and valid_integer_id?(comment_id) and is_atom(entity)

  def valid?(%{
        event_type: event_type,
        user_id: user_id,
        comment_id: comment_id
      })
      when event_type in [:update_comment, :anonymize_comment],
      do: valid_integer_id?(user_id) and valid_integer_id?(comment_id)

  #############################################################################
  ## Insight Events
  #############################################################################
  def valid?(%{event_type: event_type, user_id: user_id, insight_id: insight_id})
      when event_type in [
             :create_insight,
             :update_insight,
             :delete_insight,
             :publish_insight,
             :unpublish_insight
           ],
      do: valid_integer_id?(user_id) and valid_integer_id?(insight_id)

  #############################################################################
  ## Watchlist Events
  #############################################################################
  def valid?(%{event_type: event_type, user_id: user_id, watchlist_id: watchlist_id})
      when event_type in [:create_watchlist, :delete_watchlist],
      do: valid_integer_id?(user_id) and valid_integer_id?(watchlist_id)

  #############################################################################
  ## Apikey Events
  #############################################################################
  def valid?(%{
        event_type: event_type,
        user_id: user_id,
        token: token
      })
      when event_type in [:generate_apikey, :revoke_apikey],
      do: is_binary(token) and token != "" and valid_integer_id?(user_id)

  #############################################################################
  ## Billing Events
  #############################################################################
  def valid?(%{
        event_type: :create_stripe_customer,
        user_id: user_id,
        stripe_customer_id: customer_id
      }),
      do: valid_integer_id?(user_id) and valid_string_id?(customer_id)

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

  def valid?(
        %{
          event_type: event_type,
          subscription_id: subscription_id,
          user_id: user_id,
          stripe_subscription_id: _stripe_subscription_id
        } = event
      )
      when event_type in [
             :create_subscription,
             :update_subscription,
             :cancel_subscription_immediately,
             :renew_subscription,
             :cancel_subscription_at_period_end
           ],
      do:
        valid_integer_id?(subscription_id) and valid_integer_id?(user_id) and
          valid_subscription_stripe_id?(event)

  #############################################################################
  ## Payment Events
  #############################################################################
  def valid?(%{event_type: event_type, user_id: user_id, stripe_event_id: stripe_event_id})
      when event_type in [:payment_success, :payment_fail, :charge_fail],
      do: (is_nil(user_id) or valid_integer_id?(user_id)) and valid_string_id?(stripe_event_id)

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
        event_type: :cancel_subscription_at_period_end,
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

  #############################################################################
  ## Promoter Events
  #############################################################################
  def valid?(%{
        event_type: :create_promoter,
        user_id: user_id,
        promoter_origin: promoter_origin
      }) do
    valid_integer_id?(user_id) and is_binary(promoter_origin) and promoter_origin != ""
  end

  def valid?(%{
        event_type: event_type,
        user_id: user_id
      })
      when event_type in [
             :subscribe_biweekly_report,
             :unsubscribe_biweekly_report,
             :subscribe_monthly_newsletter,
             :unsubscribe_monthly_newsletter,
             :subscribe_metric_updates,
             :unsubscribe_metric_updates
           ] do
    valid_integer_id?(user_id)
  end

  #############################################################################
  ## Invalid Events
  #############################################################################

  def valid?(%{} = event) do
    # For testing purposes. If an event is marked as valid it will be passed. This is
    # used so a custom testing subscriber can be attached to a topic without
    # poluting the event validation here
    Map.get(event, :__internal_valid_event__) == true
  end

  # Private functions

  defp valid_integer_id?(id), do: is_integer(id) and id > 0
  defp valid_string_id?(id), do: is_binary(id) and id != ""

  defp valid_maybe_nil_string_field_change?(old, new),
    do: (is_nil(old) or is_binary(old)) and (is_nil(new) or is_binary(new)) and old != new

  defp valid_subscription_stripe_id?(%{type: :liquidity_subscription, stripe_subscription_id: id}),
    do: is_nil(id) or valid_string_id?(id)

  defp valid_subscription_stripe_id?(%{type: :nft_subscription, stripe_subscription_id: id}),
    do: is_nil(id) or valid_string_id?(id)

  defp valid_subscription_stripe_id?(%{stripe_subscription_id: id}),
    do: valid_string_id?(id)
end
