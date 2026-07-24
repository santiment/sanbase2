defmodule Sanbase.Metric.Tag.EventEmitter do
  use Sanbase.EventBus.EventEmitter

  @topic :metric_tag_events
  def topic(), do: @topic

  def handle_event({:ok, _}, :metric_tag_change = event_type, _args) do
    %{event_type: event_type}
    |> notify()
  end

  def handle_event({:error, _}, _event_type, _args) do
    :ok
  end

  defp notify(data) do
    Sanbase.EventBus.notify(%{topic: @topic, data: data})
    :ok
  end
end
