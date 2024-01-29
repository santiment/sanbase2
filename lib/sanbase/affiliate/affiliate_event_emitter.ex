defmodule Sanbase.Affiliate.EventEmitter do
  use Sanbase.EventBus.EventEmitter

  @topic :user_events
  def topic(), do: @topic

  def handle_event({:error, _}, _event_type, _extra_args), do: :ok

  def handle_event({:ok, _promoter}, :create_promoter, %{
        user: user,
        promoter_origin: promoter_origin
      }) do
    %{
      event_type: :create_promoter,
      user_id: user.id,
      promoter_origin: promoter_origin
    }
    |> notify()
  end

  defp notify(data) do
    Sanbase.EventBus.notify(%{topic: @topic, data: data})
    :ok
  end
end
