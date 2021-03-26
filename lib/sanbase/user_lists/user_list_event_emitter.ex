defmodule Sanbase.UserList.EventEmitter do
  use Sanbase.EventBus.EventEmitter
  @topic :watchlist_events

  def handle_event({:error, _} = result, _event_type, _extra_args), do: result

  def handle_event({:ok, watchlist}, event_type, _extra_args)
      when event_type in [:create_watchlist, :delete_watchlist] do
    %{event_type: event_type, user_id: watchlist.user_id, watchlist_id: watchlist.id}
    |> notify()

    {:ok, watchlist}
  end

  defp notify(data) do
    Sanbase.EventBus.notify(%{topic: @topic, data: data})
  end
end
