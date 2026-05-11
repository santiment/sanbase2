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

  def handle_event({:ok, user_trigger}, :alert_triggered, _args) do
    %{
      event_type: :alert_triggered,
      user_id: user_trigger.user_id,
      alert_id: user_trigger.id,
      alert_title: user_trigger.trigger.title,
      alert_description: user_trigger.trigger.description,
      alert_is_active: user_trigger.trigger.is_active
    }
    |> notify()
  end

  defp notify(data) do
    Sanbase.EventBus.notify(%{topic: @topic, data: data})
    :ok
  end
end
