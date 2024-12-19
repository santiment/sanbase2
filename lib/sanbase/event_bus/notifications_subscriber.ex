defmodule Sanbase.EventBus.NotificationsSubscriber do
  @moduledoc """
  Subscribe to different topics and generate notifications
  """
  use GenServer

  require Logger

  def topics(), do: ["metric_registry_events"]

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

  # Needed to handle the async tasks
  def handle_info({ref, :ok}, state) when is_reference(ref) do
    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, :normal}, state) when is_reference(ref) do
    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state) when is_reference(ref) do
    Logger.error("Metric registry notification task failed with reason: #{inspect(reason)}")
    {:noreply, state}
  end

  defp handle_event(
         %{data: %{event_type: event_type, metric: _metric}} = event,
         event_shadow,
         state
       )
       when event_type in [
              :update_metric_registry,
              :create_metric_registry,
              :delete_metric_registry
            ] do
    Task.Supervisor.async_nolink(Sanbase.TaskSupervisor, fn ->
      Sanbase.Notifications.Handler.handle_metric_registry_event(event)
    end)

    EventBus.mark_as_completed({__MODULE__, event_shadow})
    state
  end

  defp handle_event(_event, event_shadow, state) do
    EventBus.mark_as_completed({__MODULE__, event_shadow})
    state
  end
end
