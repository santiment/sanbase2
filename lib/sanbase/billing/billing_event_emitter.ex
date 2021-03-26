defmodule Sanbase.Billing.EventEmitter do
  use Sanbase.EventBus.EventEmitter

  @topic :stripe_events

  def handle_event({:error, _} = result, _event_type, _args), do: result

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

    {:ok, stripe_customer}
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

    {:ok, stripe_subscription}
  end

  def handle_event({:ok, subscription}, event_type, %{} = args)
      when event_type in [:create_subscription, :update_subscription, :delete_subscription] do
    %{
      event_type: event_type,
      subscription_id: subscription.id,
      user_id: subscription.user_id,
      stripe_subscription_id: subscription.stripe_id
    }
    |> Map.merge(args)
    |> notify()

    {:ok, subscription}
  end

  defp notify(data) do
    Sanbase.EventBus.notify(%{topic: @topic, data: data})
  end
end
