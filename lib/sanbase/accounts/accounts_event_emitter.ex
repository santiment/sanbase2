defmodule Sanbase.Accounts.EventEmitter do
  @moduledoc false
  use Sanbase.EventBus.EventEmitter

  @topic :user_events
  def topic, do: @topic

  def handle_event({:error, _}, _event, _args), do: :ok

  def handle_event({:ok, user}, :create_user, %{} = args) do
    %{event_type: :create_user, user_id: user.id}
    |> Map.merge(args)
    |> notify()
  end

  def handle_event({:ok, user}, :register_user, %{} = args) do
    %{event_type: :register_user, user_id: user.id}
    |> Map.merge(args)
    |> notify()
  end

  def handle_event({:ok, user}, :login_user, %{} = args) do
    %{event_type: :login_user, user_id: user.id}
    |> Map.merge(args)
    |> notify()
  end

  def handle_event({:ok, user}, :send_email_login_link, %{} = args) do
    %{event_type: :send_email_login_link, user_id: user.id}
    |> Map.merge(args)
    |> notify()
  end

  def handle_event({:ok, user}, :update_name, %{old_name: _, new_name: _} = args) do
    %{event_type: :update_name, user_id: user.id}
    |> Map.merge(args)
    |> notify()
  end

  def handle_event({:ok, user}, :update_username, %{old_username: _, new_username: _} = args) do
    %{event_type: :update_username, user_id: user.id}
    |> Map.merge(args)
    |> notify()
  end

  def handle_event({:ok, user}, :update_email, %{old_email: _, new_email: new_email} = args) do
    if user.stripe_customer_id do
      {:ok, _} = Sanbase.StripeApi.update_customer(user.stripe_customer_id, %{email: new_email})
    end

    %{event_type: :update_email, user_id: user.id}
    |> Map.merge(args)
    |> notify()
  end

  def handle_event({:ok, user}, :disconnect_telegram_bot, %{telegram_chat_id: telegram_chat_id} = args) do
    %{
      event_type: :disconnect_telegram_bot,
      user_id: user.id,
      telegram_chat_id: telegram_chat_id
    }
    |> Map.merge(args)
    |> notify()
  end

  def handle_event({:ok, user}, :update_email_candidate, %{email_candidate: _} = args) do
    %{event_type: :update_email_candidate, user_id: user.id}
    |> Map.merge(args)
    |> notify()
  end

  def handle_event({:ok, user_api_token}, event_type, %{user: user})
      when event_type in [:generate_apikey, :revoke_apikey] do
    notify(%{event_type: event_type, token: user_api_token.token, user_id: user.id})
  end

  def handle_event({:ok, user_follower}, event_type, _args) when event_type in [:follow_user, :unfollow_user] do
    notify(%{event_type: event_type, user_id: user_follower.user_id, follower_id: user_follower.follower_id})
  end

  defp notify(data) do
    Sanbase.EventBus.notify(%{topic: @topic, data: data})
    :ok
  end
end
