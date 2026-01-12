defmodule Sanbase.Vote.EventEmitter do
  use Sanbase.EventBus.EventEmitter

  @topic :vote_events
  def topic(), do: @topic

  def handle_event({:error, _}, _event_type, _args), do: :ok

  def handle_event({:ok, vote}, event_type, %{} = args)
      when event_type in [:create_vote, :remove_vote] do
    %{
      event_type: event_type,
      vote_id: vote.id,
      user_id: vote.user_id
    }
    |> Map.merge(args)
    |> notify()
  end

  defp notify(data) do
    Sanbase.EventBus.notify(%{topic: @topic, data: data})
    :ok
  end
end
