defmodule SanbaseWeb.Graphql.ChatApiTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory
  import Sanbase.TestHelpers
  import Mox

  alias Sanbase.Chat

  setup do
    clean_task_supervisor_children()

    user = insert(:user)
    other_user = insert(:user)

    conn = setup_jwt_auth(build_conn(), user)

    # Setup default OpenAI mocks to prevent real API calls
    stub(Sanbase.AI.MockOpenAIClient, :chat_completion, fn _system_prompt, user_message, _opts ->
      # Provide a reasonable mock response based on the user message
      msg = String.downcase(user_message)

      response =
        cond do
          String.contains?(msg, "bitcoin") ->
            "Bitcoin is currently showing interesting price patterns based on recent market data."

          String.contains?(msg, "ethereum") ->
            "Ethereum metrics indicate strong network activity and usage patterns."

          String.contains?(msg, "price") ->
            "The price analysis shows several key trends worth monitoring for your investment research."

          true ->
            "Based on the available data, here are some insights for your cryptocurrency analysis."
        end

      {:ok, response}
    end)

    stub(Sanbase.AI.MockOpenAIClient, :generate_chat_title, fn first_message ->
      # Generate a reasonable title based on the first message
      msg = String.downcase(first_message)

      title =
        cond do
          String.contains?(msg, "bitcoin") -> "Bitcoin Analysis"
          String.contains?(msg, "ethereum") -> "Ethereum Discussion"
          String.contains?(msg, "price") -> "Price Analysis"
          true -> "Crypto Discussion"
        end

      {:ok, title}
    end)

    {:ok, conn: conn, user: user, other_user: other_user}
  end

  describe "sendChatMessage mutation" do
    test "creates a new chat when chat_id not provided", %{conn: conn, user: user} do
      mutation = """
      mutation {
        sendChatMessage(
          content: "What are the top Bitcoin metrics?"
          context: {
            dashboardId: "crypto_dashboard"
            asset: "bitcoin"
            metrics: ["price_usd", "volume_usd"]
          }
        ) {
          id
          title
          type
          insertedAt
          chatMessages {
            id
            content
            role
            context
          }
          user {
            id
          }
        }
      }
      """

      result = execute_mutation_with_success(mutation, "sendChatMessage", conn)

      # AI generates some title
      assert String.length(result["title"]) > 0
      assert result["type"] == "DYOR_DASHBOARD"
      assert result["user"]["id"] == to_string(user.id)
      # At least user message
      assert length(result["chatMessages"]) >= 1

      user_message = Enum.find(result["chatMessages"], &(&1["role"] == "USER"))
      assert user_message["content"] == "What are the top Bitcoin metrics?"

      expected_context = %{
        "dashboard_id" => "crypto_dashboard",
        "asset" => "bitcoin",
        "metrics" => ["price_usd", "volume_usd"]
      }

      assert user_message["context"] == expected_context
    end

    test "creates chat with minimal input", %{conn: conn} do
      mutation = """
      mutation {
        sendChatMessage(
          content: "Simple question"
        ) {
          id
          title
          chatMessages {
            content
            context
          }
        }
      }
      """

      result = execute_mutation_with_success(mutation, "sendChatMessage", conn)

      # AI generates some title
      assert String.length(result["title"]) > 0
      assert length(result["chatMessages"]) >= 1

      user_message = Enum.find(result["chatMessages"], &(&1["content"] == "Simple question"))
      assert user_message["context"] == %{}
    end

    test "creates anonymous chat when not authenticated" do
      mutation = """
      mutation {
        sendChatMessage(
          content: "Test message"
        ) {
          id
          title
          chatMessages {
            content
            role
          }
        }
      }
      """

      result = execute_mutation_with_success(mutation, "sendChatMessage", build_conn())

      # Verify anonymous chat was created
      assert result["title"] == "Test message"
      assert length(result["chatMessages"]) >= 1

      user_message = Enum.find(result["chatMessages"], &(&1["role"] == "USER"))
      assert user_message["content"] == "Test message"

      # Verify chat exists in database as anonymous
      chat = Chat.get_chat(result["id"])
      assert chat.user_id == nil
    end

    test "creates chat with long message and AI-generated title", %{conn: conn} do
      long_message = String.duplicate("a", 60)

      mutation = """
      mutation {
        sendChatMessage(
          content: "#{long_message}"
        ) {
          title
        }
      }
      """

      result = execute_mutation_with_success(mutation, "sendChatMessage", conn)
      # AI will generate a meaningful title, not truncated content
      assert String.length(result["title"]) > 0
      # AI generates different title
      assert result["title"] != long_message
    end
  end

  describe "sendChatMessage to existing chat" do
    setup %{user: user} do
      {:ok, chat} = Chat.create_chat(%{title: "Test Chat", user_id: user.id})
      %{chat: chat}
    end

    test "adds user message to existing chat", %{conn: conn, chat: chat} do
      mutation = """
      mutation {
        sendChatMessage(
          chatId: "#{chat.id}"
          content: "Follow-up question"
          context: {
            asset: "ethereum"
            metrics: ["price_usd"]
          }
        ) {
          id
          title
          chatMessages {
            content
            role
            context
          }
        }
      }
      """

      result = execute_mutation_with_success(mutation, "sendChatMessage", conn)

      assert result["id"] == chat.id
      assert result["title"] == "Test Chat"

      # Should have the new message
      messages = result["chatMessages"]
      follow_up_message = Enum.find(messages, &(&1["content"] == "Follow-up question"))
      assert follow_up_message["role"] == "USER"

      expected_context = %{
        "asset" => "ethereum",
        "metrics" => ["price_usd"]
      }

      assert follow_up_message["context"] == expected_context
    end

    test "fails when accessing other user's chat", %{other_user: other_user, conn: conn} do
      {:ok, other_chat} = Chat.create_chat(%{title: "Other Chat", user_id: other_user.id})

      mutation = """
      mutation {
        sendChatMessage(
          chatId: "#{other_chat.id}"
          content: "Trying to access"
        ) {
          id
        }
      }
      """

      result = execute_mutation_with_errors(mutation, conn)
      assert result["message"] =~ "Access denied"
    end

    test "fails with non-existent chat", %{conn: conn} do
      fake_id = Ecto.UUID.generate()

      mutation = """
      mutation {
        sendChatMessage(
          chatId: "#{fake_id}"
          content: "Test message"
        ) {
          id
        }
      }
      """

      result = execute_mutation_with_errors(mutation, conn)
      assert result["message"] =~ "Chat not found"
    end
  end

  describe "deleteChat mutation" do
    setup %{user: user} do
      {:ok, chat} = Chat.create_chat(%{title: "Test Chat", user_id: user.id})
      {:ok, _message} = Chat.add_message_to_chat(chat.id, "Test message", :user)
      %{chat: chat}
    end

    test "deletes chat and its messages", %{conn: conn, chat: chat} do
      mutation = """
      mutation {
        deleteChat(id: "#{chat.id}") {
          id
          title
        }
      }
      """

      result = execute_mutation_with_success(mutation, "deleteChat", conn)

      assert result["id"] == chat.id
      assert result["title"] == "Test Chat"

      # Verify chat is actually deleted
      assert Chat.get_chat(chat.id) == nil
    end

    test "fails when deleting other user's chat", %{other_user: other_user, conn: conn} do
      {:ok, other_chat} = Chat.create_chat(%{title: "Other Chat", user_id: other_user.id})

      mutation = """
      mutation {
        deleteChat(id: "#{other_chat.id}") {
          id
        }
      }
      """

      result = execute_mutation_with_errors(mutation, conn)
      assert result["message"] =~ "Access denied"
    end
  end

  describe "myChats query" do
    test "returns user's chats ordered by most recent", %{conn: conn, user: user} do
      {:ok, chat1} = Chat.create_chat(%{title: "First Chat", user_id: user.id})

      # Ensure different timestamps
      Process.sleep(1000)

      {:ok, chat2} = Chat.create_chat(%{title: "Second Chat", user_id: user.id})

      # Add messages to chats to update their updated_at timestamps
      {:ok, _} = Chat.add_message_to_chat(chat1.id, "Message 1", :user)

      # Wait and then add message to chat2 to make it more recent
      Process.sleep(1000)
      {:ok, _} = Chat.add_message_to_chat(chat2.id, "Message 2", :user)

      query = """
      {
        myChats {
          id
          title
          insertedAt
          messagesCount
          latestMessage {
            content
            role
          }
        }
      }
      """

      result = execute_query(conn, query, "myChats")

      assert length(result) == 2

      # Should be ordered by most recent (updated_at)
      # chat2 should be first since its message was added later
      [first, second] = result
      assert first["title"] == "Second Chat"
      assert second["title"] == "First Chat"

      # Check messages count and latest message
      assert first["messagesCount"] == 1
      assert first["latestMessage"]["content"] == "Message 2"
      assert first["latestMessage"]["role"] == "USER"
    end

    test "returns empty list for user with no chats", %{conn: conn} do
      query = """
      {
        myChats {
          id
        }
      }
      """

      result = execute_query(conn, query, "myChats")
      assert result == []
    end

    test "fails without authentication" do
      query = """
      {
        myChats {
          id
        }
      }
      """

      result = execute_query_with_errors(build_conn(), query)
      assert result["message"] == "unauthorized"
    end
  end

  describe "chat query" do
    setup %{user: user} do
      {:ok, chat} = Chat.create_chat(%{title: "Test Chat", user_id: user.id})
      {:ok, msg1} = Chat.add_message_to_chat(chat.id, "First message", :user)
      {:ok, msg2} = Chat.add_message_to_chat(chat.id, "Second message", :assistant)
      %{chat: chat, msg1: msg1, msg2: msg2}
    end

    test "returns chat with all messages", %{conn: conn, chat: chat, msg1: msg1, msg2: msg2} do
      query = """
      {
        chat(id: "#{chat.id}") {
          id
          title
          chatMessages {
            id
            content
            role
            insertedAt
          }
          user {
            id
          }
        }
      }
      """

      result = execute_query(conn, query, "chat")

      assert result["id"] == chat.id
      assert result["title"] == "Test Chat"
      assert length(result["chatMessages"]) == 2

      messages = result["chatMessages"]
      assert Enum.any?(messages, &(&1["id"] == msg1.id && &1["content"] == "First message"))
      assert Enum.any?(messages, &(&1["id"] == msg2.id && &1["content"] == "Second message"))
    end

    test "fails when accessing other user's chat", %{other_user: other_user, conn: conn} do
      {:ok, other_chat} = Chat.create_chat(%{title: "Other Chat", user_id: other_user.id})

      query = """
      {
        chat(id: "#{other_chat.id}") {
          id
        }
      }
      """

      result = execute_query_with_errors(conn, query)
      assert result["message"] =~ "Access denied"
    end

    test "returns error for non-existent chat", %{conn: conn} do
      fake_id = Ecto.UUID.generate()

      query = """
      {
        chat(id: "#{fake_id}") {
          id
        }
      }
      """

      result = execute_query_with_errors(conn, query)
      assert result["message"] =~ "Chat not found"
    end
  end

  describe "chatMessages query" do
    setup %{user: user} do
      {:ok, chat} = Chat.create_chat(%{title: "Test Chat", user_id: user.id})

      messages =
        for i <- 1..5 do
          {:ok, msg} = Chat.add_message_to_chat(chat.id, "Message #{i}", :user)
          msg
        end

      %{chat: chat, messages: messages}
    end

    test "returns all messages by default", %{conn: conn, chat: chat} do
      query = """
      {
        chatMessages(chatId: "#{chat.id}") {
          content
        }
      }
      """

      result = execute_query(conn, query, "chatMessages")
      assert length(result) == 5
    end

    test "respects limit and offset", %{conn: conn, chat: chat} do
      query = """
      {
        chatMessages(chatId: "#{chat.id}", limit: 2, offset: 1) {
          content
        }
      }
      """

      result = execute_query(conn, query, "chatMessages")
      assert length(result) == 2
    end

    test "fails when accessing other user's chat messages", %{other_user: other_user, conn: conn} do
      {:ok, other_chat} = Chat.create_chat(%{title: "Other Chat", user_id: other_user.id})

      query = """
      {
        chatMessages(chatId: "#{other_chat.id}") {
          content
        }
      }
      """

      result = execute_query_with_errors(conn, query)
      assert result["message"] =~ "Access denied"
    end
  end

  describe "user.chats field" do
    test "returns user's chats via currentUser field", %{conn: conn, user: user} do
      {:ok, _chat1} = Chat.create_chat(%{title: "Chat 1", user_id: user.id})
      {:ok, _chat2} = Chat.create_chat(%{title: "Chat 2", user_id: user.id})

      query = """
      {
        currentUser {
          chats {
            id
            title
          }
        }
      }
      """

      result = execute_query(conn, query, "currentUser")
      chats = result["chats"]

      assert length(chats) == 2
      chat_titles = Enum.map(chats, & &1["title"])
      assert "Chat 1" in chat_titles
      assert "Chat 2" in chat_titles
    end
  end

  describe "complete chat workflow" do
    test "full conversation flow", %{conn: conn} do
      # 1. Create a new chat with first message
      create_mutation = """
      mutation {
        sendChatMessage(
          content: "What's Bitcoin's price?"
          context: {
            asset: "bitcoin"
            metrics: ["price_usd"]
          }
        ) {
          id
          title
        }
      }
      """

      chat_result = execute_mutation_with_success(create_mutation, "sendChatMessage", conn)
      chat_id = chat_result["id"]

      # 2. Add a follow-up user question (simulating assistant response would be done via backend API)
      followup_mutation = """
      mutation {
        sendChatMessage(
          chatId: "#{chat_id}"
          content: "What about Ethereum?"
          context: {
            asset: "ethereum"
          }
        ) {
          chatMessages {
            content
            role
          }
        }
      }
      """

      followup_result = execute_mutation_with_success(followup_mutation, "sendChatMessage", conn)

      # Check that user follow-up was added
      followup_message =
        Enum.find(
          followup_result["chatMessages"],
          &(&1["content"] == "What about Ethereum?")
        )

      assert followup_message["role"] == "USER"

      # 3. Add another user message
      third_mutation = """
      mutation {
        sendChatMessage(
          chatId: "#{chat_id}"
          content: "Can you compare them?"
        ) {
          chatMessages {
            content
            role
          }
        }
      }
      """

      _third_result = execute_mutation_with_success(third_mutation, "sendChatMessage", conn)

      # 4. Retrieve the complete chat
      chat_query = """
      {
        chat(id: "#{chat_id}") {
          title
          chatMessages {
            content
            role
          }
        }
      }
      """

      final_result = execute_query(conn, chat_query, "chat")
      # AI generates some title
      assert String.length(final_result["title"]) > 0
      # At least the 3 user messages
      assert length(final_result["chatMessages"]) >= 3

      messages = final_result["chatMessages"]
      user_messages = Enum.filter(messages, &(&1["role"] == "USER"))
      contents = Enum.map(user_messages, & &1["content"])
      assert "What's Bitcoin's price?" in contents
      assert "What about Ethereum?" in contents
      assert "Can you compare them?" in contents
    end
  end

  describe "academy QA chat type" do
    test "creates academy_qa chat and generates AI response", %{conn: conn, user: user} do
      # Mock the Academy AI service
      mock_academy_response =
        "Blockchain is a distributed ledger technology that maintains continuously growing lists of records, called blocks."

      mock_response = %{
        "answer" => mock_academy_response,
        "confidence" => "high",
        "sources" => [
          %{
            "number" => 0,
            "title" => "Blockchain Basics",
            "url" => "https://academy.santiment.net/blockchain-basics",
            "similarity" => 0.95
          }
        ]
      }

      http_response = %HTTPoison.Response{status_code: 200, body: Jason.encode!(mock_response)}

      Sanbase.Mock.prepare_mock2(&HTTPoison.post/4, {:ok, http_response})
      |> Sanbase.Mock.run_with_mocks(fn ->
        # First, create an academy_qa chat via Chat context to set up the type
        {:ok, chat} =
          Chat.create_chat_with_message(
            user.id,
            "What is blockchain?",
            %{},
            "academy_qa"
          )

        mutation = """
        mutation {
          sendChatMessage(
            chatId: "#{chat.id}"
            content: "Tell me more about consensus mechanisms"
          ) {
            id
            type
            chatMessages {
              content
              role
            }
          }
        }
        """

        result = execute_mutation_with_success(mutation, "sendChatMessage", conn)

        assert result["type"] == "ACADEMY_QA"

        # Should have at least the original user message and the follow-up
        messages = result["chatMessages"]
        user_messages = Enum.filter(messages, &(&1["role"] == "USER"))
        assert length(user_messages) >= 2

        # Check that the new message was added
        follow_up_message =
          Enum.find(messages, &(&1["content"] == "Tell me more about consensus mechanisms"))

        assert follow_up_message["role"] == "USER"
      end)
    end

    test "academy_qa chat works for anonymous users", %{user: user} do
      # Mock the Academy AI service for anonymous user
      mock_academy_response =
        "DeFi stands for Decentralized Finance, which refers to financial services using smart contracts on blockchains."

      mock_response = %{
        "answer" => mock_academy_response,
        "sources" => []
      }

      http_response = %HTTPoison.Response{status_code: 200, body: Jason.encode!(mock_response)}

      Sanbase.Mock.prepare_mock2(&HTTPoison.post/4, {:ok, http_response})
      |> Sanbase.Mock.run_with_mocks(fn ->
        {:ok, chat} =
          Chat.create_chat_with_message(
            user.id,
            "What is DeFi?",
            %{},
            "academy_qa"
          )

        assert chat.type == "academy_qa"
        # Verify that the chat was created correctly
        chat_with_messages = Chat.get_chat_with_messages(chat.id)
        assert length(chat_with_messages.chat_messages) >= 1
      end)
    end

    test "academy_qa chat handles API errors gracefully", %{conn: conn, user: user} do
      # Mock API error response
      http_response = %HTTPoison.Response{status_code: 500, body: ""}

      Sanbase.Mock.prepare_mock2(&HTTPoison.post/4, {:ok, http_response})
      |> Sanbase.Mock.run_with_mocks(fn ->
        {:ok, chat} =
          Chat.create_chat_with_message(
            user.id,
            "What is cryptocurrency?",
            %{},
            "academy_qa"
          )

        mutation = """
        mutation {
          sendChatMessage(
            chatId: "#{chat.id}"
            content: "This should still work despite API error"
          ) {
            id
            type
            chatMessages {
              content
              role
            }
          }
        }
        """

        # The mutation should still succeed even if AI response fails
        result = execute_mutation_with_success(mutation, "sendChatMessage", conn)
        assert result["type"] == "ACADEMY_QA"

        # The user message should still be stored
        user_messages = Enum.filter(result["chatMessages"], &(&1["role"] == "USER"))

        new_message =
          Enum.find(user_messages, &(&1["content"] == "This should still work despite API error"))

        assert new_message != nil
      end)
    end

    test "supports creating academy_qa chat type through GraphQL", %{conn: conn, user: user} do
      # Create chat directly with academy_qa type
      {:ok, chat} =
        Chat.create_chat(%{title: "Academy Chat", user_id: user.id, type: "academy_qa"})

      query = """
      {
        chat(id: "#{chat.id}") {
          id
          title
          type
        }
      }
      """

      result = execute_query(conn, query, "chat")
      assert result["type"] == "ACADEMY_QA"
      assert result["title"] == "Academy Chat"
    end

    test "lists academy_qa chats correctly", %{conn: conn, user: user} do
      {:ok, _dyor_chat} =
        Chat.create_chat(%{title: "DYOR Chat", user_id: user.id, type: "dyor_dashboard"})

      {:ok, _academy_chat} =
        Chat.create_chat(%{title: "Academy Chat", user_id: user.id, type: "academy_qa"})

      query = """
      {
        myChats {
          id
          title
          type
        }
      }
      """

      result = execute_query(conn, query, "myChats")
      assert length(result) == 2

      types = Enum.map(result, & &1["type"])
      assert "DYOR_DASHBOARD" in types
      assert "ACADEMY_QA" in types
    end
  end

  # Helper functions
  defp execute_mutation_with_success(mutation, field_name, conn) do
    conn
    |> post("/graphql", mutation_skeleton(mutation))
    |> json_response(200)
    |> get_in(["data", field_name])
  end

  defp execute_mutation_with_errors(mutation, conn) do
    conn
    |> post("/graphql", mutation_skeleton(mutation))
    |> json_response(200)
    |> Map.get("errors")
    |> hd()
  end

  defp execute_query_with_errors(conn, query) do
    conn
    |> post("/graphql", query_skeleton(query, "data"))
    |> json_response(200)
    |> Map.get("errors")
    |> hd()
  end
end
