defmodule SanbaseWeb.Graphql.Resolvers.TelegramResolver do
  import SanbaseWeb.Graphql.Helpers.Async

  alias Sanbase.Project

  def telegram_data(%{telegram_chat_name: chat_name}, _args, _resolution) do
    case chat_name do
      chat_name when is_binary(chat_name) and chat_name != "" ->
        Sanbase.Telegram.telegram_channel_members_count(chat_name)

      _ ->
        {:ok, nil}
    end
  end
end
