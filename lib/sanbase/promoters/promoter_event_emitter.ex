defmodule Sanbase.Promoters.EventEmitter do
  @behaviour Sanbase.EventBus.EventEmitter.Behaviour

  @topic :user_events

  def emit_event({:error, _} = result, _event_type, _extra_args), do: result

  def emit_event({:ok, promoter}, :create_promoter, %{
        user: user,
        promoter_origin: promoter_origin
      }) do
    %{
      event_type: :create_promoter,
      user_id: user.id,
      promoter_origin: promoter_origin
    }
    |> notify()

    {:ok, promoter}
  end

  defp notify(data) do
    Sanbase.EventBus.notify(%{
      topic: @topic,
      data: data
    })
  end
end
