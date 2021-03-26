defmodule Sanbase.Comments.EventEmitter do
  use Sanbase.EventBus.EventEmitter

  @topic :comments_topic

  def handle_event({:error, _} = result, _event_type, _args), do: result

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

    {:ok, comment}
  end

  defp notify(data) do
    Sanbase.EventBus.notify(%{
      topic: @topic,
      data: data
    })
  end
end
