defmodule Sanbase.Accounts.EventEmitter do
  @behaviour Sanbase.EventEmitter.Behaviour

  @topic :user_events

  def emit_event({:error, _} = result, _event, _args), do: result

  def emit_event({:ok, user}, :register_user, %{login_origin: _} = args) do
    Map.merge(%{event_type: :register_user, user_id: user.id}, args)
    |> notify()

    {:ok, user}
  end

  def emit_event({:ok, user}, :update_username, %{old_username: _, new_username: _} = args) do
    Map.merge(%{event_type: :update_username, user_id: user.id}, args)
    |> notify()

    {:ok, user}
  end

  def emit_event({:ok, user}, :update_email, %{old_email: _, new_email: _} = args) do
    Map.merge(%{event_type: :update_email, user_id: user.id}, args)
    |> notify()

    {:ok, user}
  end

  def emit_event({:ok, user}, :update_email_candidate, %{email_candidate: _} = args) do
    Map.merge(%{event_type: :update_email_candidate, user_id: user.id}, args)
    |> notify()

    {:ok, user}
  end

  defp notify(data) do
    Sanbase.EventBus.notify(%{topic: @topic, data: data})
  end
end
