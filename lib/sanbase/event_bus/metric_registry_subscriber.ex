defmodule Sanbase.EventBus.MetricRegistrySubscriber do
  @moduledoc """
  """
  use GenServer

  alias Sanbase.Utils.Config

  require Logger

  def topics, do: ["metric_registry_events"]

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

  def on_metric_registry_bulk_change(_event_type, _count) do
    :ok = Sanbase.Metric.Registry.refresh_stored_terms()

    :ok
  end

  def on_metric_registry_change(_event_type, _metric) do
    :ok = Sanbase.Metric.Registry.refresh_stored_terms()

    :ok
  end

  def on_metric_registry_change_test_env(event_type, metric) do
    # In test env this is the handler in order to avoid Ecto DBConnection
    # ownership errors
    Logger.warning("Metric Registry Change - Event Type: #{event_type}, Metric: #{metric}")
    :ok
  end

  defp handle_event(
         %{data: %{event_type: event_type, inserts_count: i_count, updates_count: u_count}},
         event_shadow,
         state
       )
       when event_type in [:bulk_metric_registry_change] do
    Logger.info("Start refreshing stored terms from #{__MODULE__}")

    {mod, fun} =
      Config.module_get(
        __MODULE__,
        :metric_registry_bulk_change_handler,
        {__MODULE__, :on_metric_registry_bulk_change}
      )

    :ok = apply(mod, fun, [event_type, _count = i_count + u_count])

    EventBus.mark_as_completed({__MODULE__, event_shadow})
    state
  end

  defp handle_event(%{data: %{event_type: event_type, metric: metric}}, event_shadow, state)
       when event_type in [:update_metric_registry, :create_metric_registry, :delete_metric_registry] do
    Logger.info("Start refreshing stored terms from #{__MODULE__}")

    {mod, fun} =
      Config.module_get(
        __MODULE__,
        :metric_registry_change_handler,
        {__MODULE__, :on_metric_registry_change}
      )

    :ok = apply(mod, fun, [event_type, metric])

    EventBus.mark_as_completed({__MODULE__, event_shadow})
    state
  end

  defp handle_event(%{data: %{event_type: :metrics_failed_to_load}}, event_shadow, state) do
    Logger.info("Metrics Registry failed to load. Will load data from the static files instead.")
    EventBus.mark_as_completed({__MODULE__, event_shadow})
    state
  end

  defp handle_event(event, event_shadow, state) do
    Logger.warning("Unrecognized event #{inspect(event)} received in #{__MODULE__}")
    EventBus.mark_as_completed({__MODULE__, event_shadow})
    state
  end
end
