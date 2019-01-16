defmodule SanbaseWeb.Graphql.Resolvers.TelegramResolver do
  require Logger

  alias Sanbase.Telegram

  def get_telegram_deep_link(_root, _args, %{context: %{auth: %{current_user: user}}}) do
    link = Telegram.get_or_create_deep_link(user.id)
    {:ok, link}
  end

  def get_telegram_deep_link(_root, _args, _resolution) do
    {:error, "Only logged in users can call this method"}
  end

  def revoke_telegram_deep_link(_root, _args, %{context: %{auth: %{current_user: user}}}) do
    Telegram.revoke_deep_link(user.id)
    {:ok, true}
  end

  def revoke_telegram_deep_link(_root, _args, _resolution) do
    {:error, "Only logged in users can call this method"}
  end
end
