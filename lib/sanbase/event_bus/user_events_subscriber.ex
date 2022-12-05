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
    new_state = handle_event(event, event_shadow, state)

    {:noreply, new_state}
  end

  defp handle_event(
         %{data: %{event_type: :register_user, user_id: user_id} = data},
         event_shadow,
         state
       ) do
    {:ok, _} = Sanbase.Accounts.EmailJobs.schedule_emails_after_sign_up(user_id)

    email = Sanbase.Accounts.get_user!(user_id).email
    Sanbase.Email.MailjetApi.subscribe(:monthly_newsletter, email)

    EventBus.mark_as_completed({__MODULE__, event_shadow})
    state
  end

  defp handle_event(%{data: %{event_type: :login_user, user_id: user_id}}, event_shadow, state) do
    Sanbase.Billing.maybe_create_liquidity_subscription(user_id)

    EventBus.mark_as_completed({__MODULE__, event_shadow})
    state
  end

  defp handle_event(
         %{data: %{event_type: :subscribe_monthly_newsletter, user_id: user_id}},
         event_shadow,
         state
       ) do
    email = Sanbase.Accounts.get_user!(user_id).email
    Sanbase.Email.MailjetApi.subscribe(:monthly_newsletter, email)
    EventBus.mark_as_completed({__MODULE__, event_shadow})
    state
  end

  defp handle_event(
         %{data: %{event_type: :unsubscribe_monthly_newsletter, user_id: user_id}},
         event_shadow,
         state
       ) do
    email = Sanbase.Accounts.get_user!(user_id).email
    Sanbase.Email.MailjetApi.unsubscribe(:monthly_newsletter, email)
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

  defp handle_event(_event, event_shadow, state) do
    # The unhandled events are marked as completed
    EventBus.mark_as_completed({__MODULE__, event_shadow})
    state
  end
end
