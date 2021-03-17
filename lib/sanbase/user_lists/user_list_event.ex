defmodule Sanbase.UserList.Event do
  @topic :watchlist_events

  def emit_event({:error, _} = result, _), do: result

  def emit_event({:ok, watchlist}, event_type)
      when event_type in [:create_watchlist, :delete_watchlist] do
    %{event_type: event_type, user_id: watchlist.user_id, watchlist_id: watchlist.id}
    |> notify()

    {:ok, watchlist}
  end

  defp notify(data) do
    Sanbase.EventBus.notify(%{topic: @topic, data: data})
  end
end
