defmodule Sanbase.Clickhouse.MetricAdapter.Registry.EventEmitter do
  use Sanbase.EventBus.EventEmitter

  @topic :metric_registry
  def topic(), do: @topic

  def handle_event(_, event_type, _args)
      when event_type in [
             :metrics_failed_to_load
           ] do
    %{
      event_type: event_type
    }
    |> notify()
  end

  defp notify(data) do
    Sanbase.EventBus.notify(%{topic: @topic, data: data})
    :ok
  end
end
