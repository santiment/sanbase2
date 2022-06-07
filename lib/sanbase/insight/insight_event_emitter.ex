defmodule Sanbase.Insight.EventEmitter do
  use Sanbase.EventBus.EventEmitter

  @topic :insight_events
  def topic(), do: @topic

  def handle_event({:error, _}, _event_type, _extra_args), do: :ok

  def handle_event({:ok, insight}, event_type, _args)
      when event_type in [
             :create_insight,
             :update_insight,
             :delete_insight,
             :publish_insight,
             :unpublish_insight
           ] do
    %{
      event_type: event_type,
      insight_id: insight.id,
      user_id: insight.user_id,
      insight_ready_state: insight.ready_state
    }
    |> notify()
  end

  defp notify(data) do
    Sanbase.EventBus.notify(%{topic: @topic, data: data})
    :ok
  end
end
