defmodule Sanbase.Insight.EventEmitter do
  @behaviour Sanbase.EventBus.EventEmitter.Behaviour

  @topic :insight_topic

  def emit_event({:error, _} = result, _event_type, _extra_args), do: result

  def emit_event({:ok, insight}, event_type, _args)
      when event_type in [:create_insight, :update_insight, :delete_insight, :publish_insight] do
    %{
      event_type: event_type,
      insight_id: insight.id,
      user_id: insight.user_id,
      insight_ready_state: insight.ready_state
    }
    |> notify()

    {:ok, insight}
  end

  defp notify(data) do
    Sanbase.EventBus.notify(%{
      topic: @topic,
      data: data
    })
  end
end
