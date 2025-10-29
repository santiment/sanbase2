defmodule Sanbase.EventBus.UserEventsSubscriber do
  @moduledoc """
  Export all the event bus events to a kafka topic for persistence
  """
  use GenServer

  def topics(), do: ["user_events"]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  def init(opts) do
    {:ok, opts}
  end

  def process({_topic, _id} = event_shadow) do
    GenServer.cast(__MODULE__, event_shadow)
    :ok
  end

  def handle_cast({_topic, _id} = event_shadow, state) do
    event = EventBus.fetch_event(event_shadow)

    new_state =
      Sanbase.EventBus.handle_event(
        __MODULE__,
        event,
        event_shadow,
        state,
        fn -> handle_event(event, event_shadow, state) end
      )

    {:noreply, new_state}
  end

  defp handle_event(
         %{data: %{event_type: :register_user, user_id: user_id}},
         event_shadow,
         state
       ) do
    email = Sanbase.Accounts.get_user!(user_id).email

    if email do
      Sanbase.Email.MailjetApi.client().subscribe(:monthly_newsletter, email)
      Sanbase.Email.MailjetApi.client().subscribe(:new_registrations, email)
    end

    EventBus.mark_as_completed({__MODULE__, event_shadow})
    state
  end

  defp handle_event(%{data: %{event_type: :login_user, user_id: user_id}}, event_shadow, state) do
    Sanbase.Billing.maybe_create_liquidity_subscription(user_id)

    EventBus.mark_as_completed({__MODULE__, event_shadow})
    state
  end

  defp handle_event(
         %{data: %{event_type: event_type, user_id: user_id}},
         event_shadow,
         state
       )
       when event_type in [:subscribe_monthly_newsletter] do
    email = Sanbase.Accounts.get_user!(user_id).email

    if email, do: Sanbase.Email.MailjetApi.client().subscribe(:monthly_newsletter, email)

    EventBus.mark_as_completed({__MODULE__, event_shadow})
    state
  end

  defp handle_event(
         %{data: %{event_type: event_type, user_id: user_id}},
         event_shadow,
         state
       )
       when event_type in [:unsubscribe_monthly_newsletter] do
    email = Sanbase.Accounts.get_user!(user_id).email

    if email, do: Sanbase.Email.MailjetApi.client().unsubscribe(:monthly_newsletter, email)

    EventBus.mark_as_completed({__MODULE__, event_shadow})
    state
  end

  defp handle_event(
         %{data: %{event_type: :subscribe_biweekly_pro, user_id: _user_id}},
         event_shadow,
         state
       ) do
    # email = Sanbase.Accounts.get_user!(user_id).email
    EventBus.mark_as_completed({__MODULE__, event_shadow})
    state
  end

  defp handle_event(
         %{data: %{event_type: :unsubscribe_biweekly_pro, user_id: _user_id}},
         event_shadow,
         state
       ) do
    # email = Sanbase.Accounts.get_user!(user_id).email
    EventBus.mark_as_completed({__MODULE__, event_shadow})
    state
  end

  defp handle_event(
         %{data: %{event_type: :subscribe_metric_updates, user_id: user_id}},
         event_shadow,
         state
       ) do
    email = Sanbase.Accounts.get_user!(user_id).email
    if email, do: Sanbase.Email.MailjetApi.client().subscribe(:metric_updates, email)
    EventBus.mark_as_completed({__MODULE__, event_shadow})
    state
  end

  defp handle_event(
         %{data: %{event_type: :unsubscribe_metric_updates, user_id: user_id}},
         event_shadow,
         state
       ) do
    email = Sanbase.Accounts.get_user!(user_id).email
    if email, do: Sanbase.Email.MailjetApi.client().unsubscribe(:metric_updates, email)

    EventBus.mark_as_completed({__MODULE__, event_shadow})
    state
  end

  defp handle_event(
         %{
           data: %{
             event_type: :disconnect_telegram_bot,
             user_id: _,
             telegram_chat_id: chat_id
           }
         },
         event_shadow,
         state
       ) do
    Sanbase.Telegram.send_message_to_chat_id(
      chat_id,
      "You have successfully disconnected your Telegram bot from your Sanbase profile."
    )

    EventBus.mark_as_completed({__MODULE__, event_shadow})
    state
  end

  defp handle_event(_event, event_shadow, state) do
    # The unhandled events are marked as completed
    EventBus.mark_as_completed({__MODULE__, event_shadow})
    state
  end
end
