defmodule Sanbase.Comments.EventEmitter do
  @moduledoc false
  use Sanbase.EventBus.EventEmitter

  @topic :comment_topic
  def topic, do: @topic

  def handle_event({:error, _}, _event_type, _args), do: :ok

  # entity is one of :insight, :timeline_event, etc.
  def handle_event({:ok, comment}, event_type, %{} = args)
      when event_type in [:create_comment, :update_comment, :anonymize_comment] do
    %{
      event_type: event_type,
      comment_id: comment.id,
      user_id: comment.user_id
    }
    |> Map.merge(args)
    |> notify()
  end

  defp notify(data) do
    Sanbase.EventBus.notify(%{topic: @topic, data: data})
    :ok
  end
end
