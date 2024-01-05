defmodule Sanbase.Alert.EventEmitter do
  use Sanbase.EventBus.EventEmitter

  @topic :alert_events
  def topic(), do: @topic

  def handle_event({:error, _}, _even_type, _args), do: :ok

  def handle_event({:ok, alert}, event_type, _args)
      when event_type in [:create_alert, :delete_alert] do
    %{user_id: alert.user_id, alert_id: alert.id, event_type: event_type}
    |> notify()
  end

  defp notify(data) do
    Sanbase.EventBus.notify(%{topic: @topic, data: data})
    :ok
  end
end
