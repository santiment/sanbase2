defmodule Sanbase.ChatTest do
  use Sanbase.DataCase, async: true

  import Sanbase.Factory
  alias Sanbase.Chat

  describe "create_chat_with_message/3" do
    test "creates a chat with initial user message" do
      user = insert(:user)
      content = "What are the top metrics for Bitcoin analysis?"

      context = %{
        "dashboard_id" => "dash_123",
        "asset" => "bitcoin",
        "metrics" => ["price_usd", "dev_activity"]
      }

      assert {:ok, chat} = Chat.create_chat_with_message(user.id, content, context)
      assert chat.title == content
      assert chat.user_id == user.id
      assert length(chat.chat_messages) == 1

      [message] = chat.chat_messages
      assert message.content == content
      assert message.role == :user
      assert message.context == context
    end

    test "generates truncated title for long content" do
      user = insert(:user)
      long_content = String.duplicate("a", 60)
      expected_title = String.slice(long_content, 0, 50) <> "..."

      assert {:ok, chat} = Chat.create_chat_with_message(user.id, long_content)
      assert chat.title == expected_title
    end

    test "fails with invalid user_id" do
      content = "What are the top metrics for Bitcoin analysis?"

      assert {:error, changeset} = Chat.create_chat_with_message(999_999, content)
      assert "does not exist" in errors_on(changeset).user_id
    end
  end

  describe "create_chat/1" do
    test "creates a chat with valid attributes" do
      user = insert(:user)
      attrs = %{title: "Bitcoin Analysis Chat", user_id: user.id}

      assert {:ok, chat} = Chat.create_chat(attrs)
      assert chat.title == "Bitcoin Analysis Chat"
      assert chat.user_id == user.id
    end

    test "fails with missing required fields" do
      assert {:error, changeset} = Chat.create_chat(%{})

      errors = errors_on(changeset)
      assert "can't be blank" in errors.title
      assert "can't be blank" in errors.user_id
    end

    test "fails with empty title" do
      user = insert(:user)
      attrs = %{title: "", user_id: user.id}

      assert {:error, changeset} = Chat.create_chat(attrs)
      assert "can't be blank" in errors_on(changeset).title
    end
  end

  describe "add_message_to_chat/4" do
    setup do
      user = insert(:user)
      {:ok, chat} = Chat.create_chat(%{title: "Test Chat", user_id: user.id})
      %{user: user, chat: chat}
    end

    test "adds user message with context", %{chat: chat} do
      content = "Show me Bitcoin price trends"

      context = %{
        "dashboard_id" => "dash_456",
        "asset" => "bitcoin",
        "metrics" => ["price_usd"]
      }

      assert {:ok, message} = Chat.add_message_to_chat(chat.id, content, :user, context)
      assert message.content == content
      assert message.role == :user
      assert message.context == context
      assert message.chat_id == chat.id
    end

    test "adds assistant message", %{chat: chat} do
      content = "Here's the Bitcoin price analysis..."

      assert {:ok, message} = Chat.add_message_to_chat(chat.id, content, :assistant)
      assert message.content == content
      assert message.role == :assistant
      assert message.context == %{}
    end

    test "fails with invalid role", %{chat: chat} do
      assert {:error, changeset} = Chat.add_message_to_chat(chat.id, "test", :invalid_role)
      refute changeset.valid?
      assert changeset.errors[:role]
    end

    test "fails with invalid context keys", %{chat: chat} do
      invalid_context = %{"invalid_key" => "value"}

      assert {:error, changeset} =
               Chat.add_message_to_chat(chat.id, "test", :user, invalid_context)

      assert "contains invalid keys: invalid_key" in errors_on(changeset).context
    end

    test "fails with invalid metrics format", %{chat: chat} do
      invalid_context = %{"metrics" => "not_a_list"}

      assert {:error, changeset} =
               Chat.add_message_to_chat(chat.id, "test", :user, invalid_context)

      assert "metrics must be a list" in errors_on(changeset).context
    end

    test "fails with non-string metrics", %{chat: chat} do
      invalid_context = %{"metrics" => [123, 456]}

      assert {:error, changeset} =
               Chat.add_message_to_chat(chat.id, "test", :user, invalid_context)

      assert "metrics must be a list of strings" in errors_on(changeset).context
    end
  end

  describe "add_assistant_response/3" do
    setup do
      user = insert(:user)
      {:ok, chat} = Chat.create_chat(%{title: "Test Chat", user_id: user.id})
      %{chat: chat}
    end

    test "adds assistant response with context", %{chat: chat} do
      content = "Based on the data, Bitcoin shows strong momentum"
      context = %{"asset" => "bitcoin"}

      assert {:ok, message} = Chat.add_assistant_response(chat.id, content, context)
      assert message.role == :assistant
      assert message.content == content
      assert message.context == context
    end
  end

  describe "get_chat_with_messages/1" do
    test "returns chat with messages ordered by insertion time" do
      user = insert(:user)
      {:ok, chat} = Chat.create_chat(%{title: "Test Chat", user_id: user.id})

      {:ok, msg1} = Chat.add_message_to_chat(chat.id, "First message", :user)
      Process.sleep(10)
      {:ok, msg2} = Chat.add_message_to_chat(chat.id, "Second message", :assistant)

      result = Chat.get_chat_with_messages(chat.id)
      assert result.id == chat.id
      assert length(result.chat_messages) == 2

      [first, second] = result.chat_messages
      assert first.id == msg1.id
      assert second.id == msg2.id
    end

    test "returns nil for non-existent chat" do
      non_existent_id = Ecto.UUID.generate()
      assert Chat.get_chat_with_messages(non_existent_id) == nil
    end
  end

  describe "list_user_chats/1" do
    test "returns user's chats ordered by most recent" do
      user = insert(:user)
      other_user = insert(:user)

      {:ok, chat1} = Chat.create_chat(%{title: "First Chat", user_id: user.id})

      # Sleep to ensure different timestamps
      Process.sleep(1000)

      {:ok, chat2} = Chat.create_chat(%{title: "Second Chat", user_id: user.id})

      # Sleep again and update chat2 to ensure it has a newer updated_at timestamp
      Process.sleep(1000)
      {:ok, updated_chat2} = Chat.update_chat_title(chat2.id, "Updated Second Chat")

      {:ok, _other_chat} = Chat.create_chat(%{title: "Other User Chat", user_id: other_user.id})

      chats = Chat.list_user_chats(user.id)
      assert length(chats) == 2

      [first, second] = chats

      # Verify that the first chat is the one that was updated most recently
      assert first.id == updated_chat2.id
      assert second.id == chat1.id

      # Also verify the updated_at timestamps are properly ordered
      assert NaiveDateTime.compare(first.updated_at, second.updated_at) == :gt
    end

    test "returns empty list for user with no chats" do
      user = insert(:user)
      assert Chat.list_user_chats(user.id) == []
    end
  end

  describe "delete_chat/1" do
    test "deletes chat and its messages" do
      user = insert(:user)
      {:ok, chat} = Chat.create_chat(%{title: "Test Chat", user_id: user.id})
      {:ok, _message} = Chat.add_message_to_chat(chat.id, "Test message", :user)

      assert {:ok, deleted_chat} = Chat.delete_chat(chat.id)
      assert deleted_chat.id == chat.id

      assert Chat.get_chat(chat.id) == nil
      assert Chat.get_chat_messages(chat.id) == []
    end

    test "returns error for non-existent chat" do
      non_existent_id = Ecto.UUID.generate()
      assert {:error, :not_found} = Chat.delete_chat(non_existent_id)
    end
  end

  describe "update_chat_title/2" do
    test "updates chat title" do
      user = insert(:user)
      {:ok, chat} = Chat.create_chat(%{title: "Old Title", user_id: user.id})

      assert {:ok, updated_chat} = Chat.update_chat_title(chat.id, "New Title")
      assert updated_chat.title == "New Title"
    end

    test "returns error for non-existent chat" do
      non_existent_id = Ecto.UUID.generate()
      assert {:error, :not_found} = Chat.update_chat_title(non_existent_id, "New Title")
    end
  end

  describe "get_chat_messages/2" do
    setup do
      user = insert(:user)
      {:ok, chat} = Chat.create_chat(%{title: "Test Chat", user_id: user.id})

      messages =
        for i <- 1..5 do
          {:ok, msg} = Chat.add_message_to_chat(chat.id, "Message #{i}", :user)
          msg
        end

      %{chat: chat, messages: messages}
    end

    test "returns all messages by default", %{chat: chat, messages: messages} do
      result = Chat.get_chat_messages(chat.id)
      assert length(result) == 5
      assert Enum.map(result, & &1.id) == Enum.map(messages, & &1.id)
    end

    test "respects limit option", %{chat: chat} do
      result = Chat.get_chat_messages(chat.id, limit: 3)
      assert length(result) == 3
    end

    test "respects offset option", %{chat: chat} do
      result = Chat.get_chat_messages(chat.id, offset: 2, limit: 2)
      assert length(result) == 2
    end
  end

  describe "complete chat workflow" do
    test "creates chat, adds messages, and retrieves conversation" do
      user = insert(:user)

      initial_content = "What's the current price of Bitcoin?"

      initial_context = %{
        "dashboard_id" => "crypto_dashboard",
        "asset" => "bitcoin",
        "metrics" => ["price_usd", "market_cap_usd"]
      }

      assert {:ok, chat} =
               Chat.create_chat_with_message(user.id, initial_content, initial_context)

      assistant_response =
        "Bitcoin is currently trading at $45,000 USD with a market cap of $850B."

      assert {:ok, _} = Chat.add_assistant_response(chat.id, assistant_response)

      follow_up = "What about Ethereum?"

      follow_up_context = %{
        "dashboard_id" => "crypto_dashboard",
        "asset" => "ethereum",
        "metrics" => ["price_usd"]
      }

      assert {:ok, _} = Chat.add_message_to_chat(chat.id, follow_up, :user, follow_up_context)

      final_chat = Chat.get_chat_with_messages(chat.id)
      assert length(final_chat.chat_messages) == 3

      [msg1, msg2, msg3] = final_chat.chat_messages
      assert msg1.role == :user
      assert msg1.content == initial_content
      assert msg1.context == initial_context

      assert msg2.role == :assistant
      assert msg2.content == assistant_response

      assert msg3.role == :user
      assert msg3.content == follow_up
      assert msg3.context == follow_up_context
    end
  end
end
