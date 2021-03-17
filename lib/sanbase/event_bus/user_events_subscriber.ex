defmodule Sanbase.EventBus.UserEventsSubscriber do
  @moduledoc """
  Export all the event bus events to a kafka topic for persistence
  """
  use GenServer

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

  defp handle_event(%{data: %{event_type: :update_email}}, event_shadow, state) do
    # msg = "The email of sanbae has been changed"
    # Madril.send(user, msg)
    EventBus.mark_as_completed({{__MODULE__, %{}}, event_shadow})
    state
  end

  defp handle_event(%{data: %{event_type: :update_username}}, event_shadow, state) do
    # Do something
    EventBus.mark_as_completed({{__MODULE__, %{}}, event_shadow})
    state
  end

  defp handle_event(_event, event_shadow, state) do
    # The unhandled events are marked as completed
    EventBus.mark_as_completed({{__MODULE__, %{}}, event_shadow})
    state
  end
end
