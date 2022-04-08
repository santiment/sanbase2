defmodule Sanbase.EventBus.BillingEventSubscriber do
  use GenServer

  alias Sanbase.{Accounts, ApiCallLimit}

  require Logger

  def topics(), do: ["billing_events"]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  def init(opts), do: {:ok, opts}

  def process({_topic, _id} = event_shadow) do
    GenServer.cast(__MODULE__, event_shadow)
  end

  def handle_cast({_topic, _id} = event_shadow, state) do
    event = EventBus.fetch_event(event_shadow)
    event_type = event.data.event_type

    handle_event(event_type, event, event_shadow)
    {:noreply, state}
  end

  @subscription_events [
    :create_subscription,
    :update_subscription,
    :delete_subscription,
    :cancel_subscription,
    :renew_subscription
  ]

  @payment_events [:payment_success, :payment_fail, :charge_fail]

  @handler_types [
    :update_api_call_limit_table,
    :send_discord_notification,
    :unfreeze_user_frozen_alerts
  ]

  @doc false
  defp handle_event(event_type, event, event_shadow) do
    Enum.each(@handler_types, fn type ->
      try do
        do_handle(type, event_type, event)
      rescue
        e ->
          Logger.error("Raised #{Exception.message(e)} while handling #{event_type}")
      end
    end)

    :ok = EventBus.mark_as_completed({__MODULE__, event_shadow})
  end

  defp do_handle(:update_api_call_limit_table, event_type, event)
       when event_type in @subscription_events do
    event.data.user_id
    |> Accounts.get_user()
    |> case do
      {:ok, user} ->
        ApiCallLimit.update_user_plan(user)

      _ ->
        :ok
    end
  end

  defp do_handle(:send_discord_notification, event_type, event)
       when event_type in @subscription_events or event_type in @payment_events do
    Sanbase.Billing.DiscordNotification.handle_event(event_type, event)
  end

  defp do_handle(:unfreeze_user_frozen_alerts, event_type, event)
       when event_type in [:create_subscription, :update_subscription, :renew_subscription] do
    case Sanbase.Billing.Subscription.user_has_sanbase_pro?(event.data.user_id) do
      true ->
        Logger.info(
          "[BillingEventSubscriber] Unfreezing alerts for user with id #{event.data.user_id}"
        )

        :ok = Sanbase.Alert.UserTrigger.unfreeze_user_frozen_alerts(event.data.user_id)

      false ->
        :ok
    end
  end

  defp do_handle(_type, _event_type, _event) do
    :ok
  end
end
