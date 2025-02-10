defmodule SanbaseWeb.Graphql.Resolvers.TelegramResolver do
  @moduledoc false
  alias Sanbase.Telegram

  require Logger

  def is_telegram_chat_id_valid(_root, %{chat_id: chat_id}, _resolution) do
    {:ok, Sanbase.Telegram.channel_id_valid?(chat_id)}
  end

  def get_telegram_deep_link(_root, _args, %{context: %{auth: %{auth_method: :user_token, current_user: user}}}) do
    link = Telegram.get_or_create_deep_link(user.id)
    {:ok, link}
  end

  def get_telegram_deep_link(_root, _args, _resolution) do
    {:error, "Only logged in users can call this method"}
  end

  def revoke_telegram_deep_link(_root, _args, %{context: %{auth: %{auth_method: :user_token, current_user: user}}}) do
    Telegram.revoke_deep_link(user.id)
    {:ok, true}
  end

  def revoke_telegram_deep_link(_root, _args, _resolution) do
    {:error, "Only logged in users can call this method"}
  end
end
