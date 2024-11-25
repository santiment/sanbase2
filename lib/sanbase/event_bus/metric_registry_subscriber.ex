defmodule Sanbase.EventBus.MetricRegistrySubscriber do
  @moduledoc """
  Subscribe to all events and generate notifications that will be shown on sanbase
  """
  use GenServer

  alias Sanbase.Utils.Config

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
    state = handle_event(event, event_shadow, state)
    {:noreply, state}
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

  def on_metric_registry_change(_event_type, _metric) do
    # Do not change the order here
    true = Sanbase.Clickhouse.MetricAdapter.Registry.refresh_stored_terms()
    true = Sanbase.Metric.Helper.refresh_stored_terms()
    true = Sanbase.Billing.Plan.StandardAccessChecker.refresh_stored_terms()

    :ok
  end

  def on_metric_registry_change_test_env(event_type, metric) do
    # In test env this is the handler in order to avoid Ecto DBConnection
    # ownership errors
    Logger.warning("Metric Registry Change - Event Type: #{event_type}, Metric: #{metric}")
    :ok
  end

  defp handle_event(
         %{data: %{event_type: event_type, metric: metric}} = event,
         event_shadow,
         state
       )
       when event_type in [
              :update_metric_registry,
              :create_metric_registry,
              :delete_metric_registry
            ] do
    Logger.info("Start refreshing stored terms from #{__MODULE__}")

    {mod, fun} =
      Config.module_get(
        __MODULE__,
        :metric_registry_change_handler,
        {__MODULE__, :on_metric_registry_change}
      )

    :ok = apply(mod, fun, [event_type, metric])

    Task.Supervisor.async_nolink(Sanbase.TaskSupervisor, fn ->
      Sanbase.Notifications.Handler.handle_metric_registry_event(event)
    end)

    EventBus.mark_as_completed({__MODULE__, event_shadow})
    state
  end

  defp handle_event(
         %{data: %{event_type: :metrics_failed_to_load}},
         event_shadow,
         state
       ) do
    Logger.info("Metrics Registry failed to load. Will load data from the static files instead.")
    EventBus.mark_as_completed({__MODULE__, event_shadow})
    state
  end

  defp handle_event(_event, event_shadow, state) do
    :ok = EventBus.mark_as_completed({__MODULE__, event_shadow})
    state
  end
end
