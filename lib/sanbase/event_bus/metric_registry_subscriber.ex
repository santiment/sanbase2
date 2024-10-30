defmodule Sanbase.EventBus.MetricRegistrySubscriber do
  @moduledoc """
  Subscribe to all events and generate notifications that will be shown on sanbase
  """
  use GenServer

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
    state = handle_event(event, event_shadow, state)
    {:noreply, state}
  end

  defp handle_event(
         %{data: %{event_type: event_type}},
         event_shadow,
         state
       )
       when event_type in [
              :update_metric_registry,
              :create_metric_registry,
              :delete_metric_registry
            ] do
    Sanbase.Clickhouse.MetricAdapter.Registry.refresh_stored_terms()
    Sanbase.Billing.Plan.StandardAccessChecker.refresh_stored_terms()

    EventBus.mark_as_completed({__MODULE__, event_shadow})
    state
  end

  defp handle_event(
         %{data: %{event_type: :metrics_failed_to_load}},
         event_shadow,
         state
       ) do
    Logger.info("Metrics Registry failed to load")
    EventBus.mark_as_completed({__MODULE__, event_shadow})
    state
  end

  defp handle_event(_event, event_shadow, state) do
    :ok = EventBus.mark_as_completed({__MODULE__, event_shadow})
    state
  end
end
