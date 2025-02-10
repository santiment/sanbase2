defmodule Sanbase.UserList.EventEmitter do
  @moduledoc false
  use Sanbase.EventBus.EventEmitter

  @topic :watchlist_events
  def topic, do: @topic

  def handle_event({:error, _}, _event_type, _extra_args), do: :ok

  def handle_event({:ok, watchlist}, event_type, _extra_args) when event_type in [:create_watchlist, :delete_watchlist] do
    notify(%{event_type: event_type, user_id: watchlist.user_id, watchlist_id: watchlist.id})
  end

  defp notify(data) do
    Sanbase.EventBus.notify(%{topic: @topic, data: data})

    :ok
  end
end
