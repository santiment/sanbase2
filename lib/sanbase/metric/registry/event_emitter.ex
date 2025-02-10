defmodule Sanbase.Metric.Registry.EventEmitter do
  @moduledoc false
  use Sanbase.EventBus.EventEmitter

  @topic :metric_registry_events
  def topic, do: @topic

  def handle_event(_, event_type, _args) when event_type in [:metrics_failed_to_load] do
    notify(%{event_type: event_type})
  end

  def handle_event({:ok, map}, event_type, args) when event_type in [:bulk_metric_registry_change] do
    %{event_type: event_type}
    |> Map.merge(map)
    |> Map.merge(args)
    |> notify()
  end

  def handle_event({:ok, struct}, event_type, args)
      when event_type in [:create_metric_registry, :update_metric_registry, :delete_metric_registry] do
    %{event_type: event_type, id: struct.id, metric: struct.metric}
    |> Map.merge(args)
    |> notify()
  end

  def handle_event({:error, _changeset}, _event_type, _args) do
    :ok
  end

  defp notify(data) do
    Sanbase.EventBus.notify(%{topic: @topic, data: data})
    :ok
  end
end
