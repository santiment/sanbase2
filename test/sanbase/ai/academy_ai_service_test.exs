defmodule Sanbase.AI.AcademyAIServiceTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory
  import Mox

  alias Sanbase.Chat

  setup :verify_on_exit!

  setup do
    user = insert(:user)

    {:ok, chat} =
      Chat.create_chat(%{
        title: "Academy Test Chat",
        user_id: user.id,
        type: "academy_qa"
      })

    # Add some chat history
    {:ok, _msg1} = Chat.add_message_to_chat(chat.id, "What is DeFi?", :user, %{})

    {:ok, _msg2} =
      Chat.add_message_to_chat(
        chat.id,
        "DeFi stands for Decentralized Finance...",
        :assistant,
        %{}
      )

    %{
      user: user,
      chat: chat
    }
  end
end
