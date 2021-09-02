defmodule Sanbase.Accounts.EventEmitter do
  use Sanbase.EventBus.EventEmitter
  alias Sanbase.Billing

  @topic :user_events
  def topic(), do: @topic

  def handle_event({:error, _}, _event, _args), do: :ok

  def handle_event({:ok, user}, :register_user, %{login_origin: _} = args) do
    Sanbase.Accounts.Email.schedule_emails_after_sign_up(user)

    Map.merge(%{event_type: :register_user, user_id: user.id}, args)
    |> notify()
  end

  def handle_event({:ok, user}, :login_user, %{login_origin: _} = args) do
    Billing.maybe_create_liquidity_subscription_async(user.id)

    Map.merge(%{event_type: :login_user, user_id: user.id}, args)
    |> notify()
  end

  def handle_event({:ok, user}, :update_username, %{old_username: _, new_username: _} = args) do
    Map.merge(%{event_type: :update_username, user_id: user.id}, args)
    |> notify()
  end

  def handle_event({:ok, user}, :update_email, %{old_email: _, new_email: _} = args) do
    Map.merge(%{event_type: :update_email, user_id: user.id}, args)
    |> notify()
  end

  def handle_event({:ok, user}, :update_email_candidate, %{email_candidate: _} = args) do
    Map.merge(%{event_type: :update_email_candidate, user_id: user.id}, args)
    |> notify()
  end

  def handle_event({:ok, user_api_token}, event_type, %{user: user})
      when event_type in [:generate_apikey, :revoke_apikey] do
    %{event_type: event_type, token: user_api_token.token, user_id: user.id}
    |> notify()
  end

  def handle_event({:ok, user_follower}, event_type, _extra_args)
      when event_type in [:follow_user, :unfollow_user] do
    %{
      event_type: event_type,
      user_id: user_follower.user_id,
      follower_id: user_follower.follower_id
    }
    |> notify()
  end

  defp notify(data) do
    Sanbase.EventBus.notify(%{topic: @topic, data: data})
    :ok
  end
end
