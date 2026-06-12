defmodule Sanbase.TelegramBot.BotMessage do
  @moduledoc """
  Maps Telegram messages sent by the Q&A bot to their conversation id.

  Telegram's `reply_to_message` is only one level deep, so a reply chain cannot
  be walked from an update alone. Instead, every answer message the bot sends is
  recorded here. When a user replies to one of the bot's messages, the replied-to
  message id is looked up to find which conversation to continue.
  """

  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Repo

  schema "telegram_bot_messages" do
    field(:chat_id, :string)
    field(:message_id, :integer)
    field(:conversation_id, :string)

    timestamps()
  end

  def store(chat_id, message_id, conversation_id) do
    %__MODULE__{}
    |> cast(
      %{
        chat_id: to_string(chat_id),
        message_id: message_id,
        conversation_id: conversation_id
      },
      [:chat_id, :message_id, :conversation_id]
    )
    |> validate_required([:chat_id, :message_id, :conversation_id])
    |> Repo.insert(on_conflict: :nothing)
  end

  def conversation_for(chat_id, message_id) do
    from(m in __MODULE__,
      where: m.chat_id == ^to_string(chat_id) and m.message_id == ^message_id,
      select: m.conversation_id
    )
    |> Repo.one()
  end
end
