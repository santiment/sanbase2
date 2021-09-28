defmodule Sanbase.Billing.EventEmitter do
  use Sanbase.EventBus.EventEmitter

  alias Sanbase.Accounts.User

  @topic :billing_events
  def topic(), do: @topic

  def handle_event({:error, _}, _event_type, _args), do: :ok

  def handle_event({:ok, stripe_customer}, event_type, %{
        user: user,
        card_token: card_token
      })
      when event_type in [:create_stripe_customer, :update_stripe_customer] do
    %{
      event_type: event_type,
      user_id: user.id,
      stripe_customer_id: stripe_customer.id,
      card_token: card_token
    }
    |> notify()
  end

  def handle_event({:ok, stripe_subscription}, :create_stripe_subscription, %{
        user: user,
        card_token: card_token
      }) do
    %{
      event_type: :create_stripe_subscription,
      user_id: user.id,
      card_token: card_token,
      stripe_subscription_id: stripe_subscription.id
    }
    |> notify()
  end

  def handle_event({:ok, stripe_event}, event_type, %{} = args)
      when event_type in [:payment_success, :payment_fail] do
    object = stripe_event["data"]["object"]

    %{
      event_type: event_type,
      user_id: stripe_event_to_user_id(stripe_event),
      stripe_event_id: stripe_event["id"],
      invoice_url: object["hosted_invoice_url"],
      total_amount: object["total"] || object["amount"],
      total: object["total"],
      amount: object["amount"],
      starting_balance: object["starting_balance"],
      coupon_id: object["discount"]["coupon"]["id"],
      coupon_name: object["discount"]["coupon"]["name"],
      coupon_percent_off: object["discount"]["coupon"]["percent_off"],
      extra_in_memory_data: %{stripe_event: stripe_event}
    }
    |> Map.merge(args)
    |> notify()
  end

  def handle_event({:ok, stripe_event}, :charge_fail = event_type, %{} = args) do
    object = stripe_event["data"]["object"]

    %{
      event_type: event_type,
      user_id: stripe_event_to_user_id(stripe_event),
      stripe_event_id: stripe_event["id"],
      total_amount: object["total"] || object["amount"],
      total: object["total"],
      amount: object["amount"],
      extra_in_memory_data: %{stripe_event: stripe_event}
    }
    |> Map.merge(args)
    |> notify()
  end

  def handle_event({:ok, subscription}, event_type, %{} = args)
      when event_type in [
             :create_subscription,
             :update_subscription,
             :delete_subscription,
             :renew_subscription,
             :cancel_subscription
           ] do
    %{
      event_type: event_type,
      subscription_id: subscription.id,
      user_id: subscription.user_id,
      stripe_subscription_id: subscription.stripe_id,
      extra_in_memory_data: %{subscription: subscription}
    }
    |> Map.merge(args)
    |> notify()
  end

  defp notify(data) do
    Sanbase.EventBus.notify(%{topic: @topic, data: data})
    :ok
  end

  defp stripe_event_to_user_id(stripe_event) do
    with customer_id when not is_nil(customer_id) <- stripe_event["data"]["object"]["customer"],
         {:ok, %User{id: user_id}} <- User.by_stripe_customer_id(customer_id) do
      user_id
    else
      _ -> nil
    end
  end
end
