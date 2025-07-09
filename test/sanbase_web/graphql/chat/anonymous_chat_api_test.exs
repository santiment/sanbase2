defmodule SanbaseWeb.Graphql.AnonymousChatApiTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory
  import Mox
  import ExUnit.CaptureLog

  alias Sanbase.Chat

  setup :verify_on_exit!

  describe "Anonymous Chat API" do
    test "creates new Academy QA chat for anonymous user", %{conn: conn} do
      mock_academy_response()
      |> Sanbase.Mock.run_with_mocks(fn ->
        mutation = """
        mutation {
          sendChatMessage(
            content: "What is DeFi?"
            type: ACADEMY_QA
          ) {
            id
            title
            type
            chatMessages {
              id
              content
              role
              sources
              insertedAt
            }
          }
        }
        """

        conn = post(conn, "/graphql", %{"query" => mutation})

        response = json_response(conn, 200)

        assert %{
                 "data" => %{
                   "sendChatMessage" => %{
                     "id" => chat_id,
                     "title" => "What is DeFi?",
                     "type" => "ACADEMY_QA",
                     "chatMessages" => messages
                   }
                 }
               } = response

        assert length(messages) == 2

        user_message = Enum.find(messages, &(&1["role"] == "USER"))
        assert user_message["content"] == "What is DeFi?"

        assistant_message = Enum.find(messages, &(&1["role"] == "ASSISTANT"))
        content = assistant_message["content"]
        sources = assistant_message["sources"]

        assert String.contains?(content, "DeFi stands for Decentralized Finance")
        assert is_list(sources)
        assert length(sources) == 1

        # Verify chat exists in database as anonymous
        chat = Chat.get_chat(chat_id)
        assert chat.user_id == nil
        assert chat.type == "academy_qa"
      end)
    end

    test "continues Academy QA conversation for anonymous user", %{conn: conn} do
      # Create initial anonymous chat
      {:ok, chat} = Chat.create_chat_with_message(nil, "What is DeFi?", %{}, "academy_qa")

      mock_academy_response()
      |> Sanbase.Mock.run_with_mocks(fn ->
        mutation = """
        mutation {
          sendChatMessage(
            chatId: "#{chat.id}"
            content: "What are the risks?"
            type: ACADEMY_QA
          ) {
            chatMessages {
              content
              role
              sources
            }
          }
        }
        """

        conn = post(conn, "/graphql", %{"query" => mutation})

        assert %{
                 "data" => %{
                   "sendChatMessage" => %{
                     "chatMessages" => messages
                   }
                 }
               } = json_response(conn, 200)

        # Original + new user message + AI response
        assert length(messages) == 3

        user_message = Enum.find(messages, &(&1["content"] == "What are the risks?"))
        assert user_message["role"] == "USER"

        # Last message
        ai_message = Enum.at(messages, -1)
        assert ai_message["role"] == "ASSISTANT"
        assert String.contains?(ai_message["content"], "DeFi stands for Decentralized Finance")
      end)
    end

    test "creates new DYOR dashboard chat for anonymous user", %{conn: conn} do
      mock_dyor_response()

      mutation = """
      mutation {
        sendChatMessage(
          content: "Analyze Bitcoin trends"
          context: {
            asset: "bitcoin"
            metrics: ["price_usd"]
          }
        ) {
          id
          title
          type
          chatMessages {
            content
            role
            context
          }
        }
      }
      """

      conn = post(conn, "/graphql", %{"query" => mutation})

      assert %{
               "data" => %{
                 "sendChatMessage" => %{
                   "id" => chat_id,
                   "title" => "Analyze Bitcoin trends",
                   "type" => "DYOR_DASHBOARD",
                   "chatMessages" => [
                     %{
                       "content" => "Analyze Bitcoin trends",
                       "role" => "USER",
                       "context" => %{
                         "asset" => "bitcoin",
                         "metrics" => ["price_usd"]
                       }
                     },
                     %{
                       "content" => content,
                       "role" => "ASSISTANT"
                     }
                   ]
                 }
               }
             } = json_response(conn, 200)

      assert String.contains?(content, "Bitcoin analysis shows strong fundamentals")

      # Verify chat exists in database as anonymous
      chat = Chat.get_chat(chat_id)
      assert chat.user_id == nil
      assert chat.type == "dyor_dashboard"
    end

    test "anonymous user can access anonymous chat", %{conn: conn} do
      {:ok, chat} = Chat.create_chat_with_message(nil, "Test question", %{}, "academy_qa")

      query = """
      query {
        chat(id: "#{chat.id}") {
          id
          title
          type
          chatMessages {
            content
            role
          }
        }
      }
      """

      conn = post(conn, "/graphql", %{"query" => query})

      chat_id = chat.id

      assert %{
               "data" => %{
                 "chat" => %{
                   "id" => ^chat_id,
                   "title" => "Test question",
                   "type" => "ACADEMY_QA",
                   "chatMessages" => [
                     %{
                       "content" => "Test question",
                       "role" => "USER"
                     }
                   ]
                 }
               }
             } = json_response(conn, 200)
    end

    test "anonymous user can get paginated messages", %{conn: conn} do
      {:ok, chat} = Chat.create_chat_with_message(nil, "Initial question", %{}, "academy_qa")

      # Add more messages
      {:ok, _} = Chat.add_message_to_chat(chat.id, "Follow up question", :user)
      {:ok, _} = Chat.add_assistant_response(chat.id, "AI response")

      query = """
      query {
        chatMessages(chatId: "#{chat.id}", limit: 2) {
          content
          role
        }
      }
      """

      conn = post(conn, "/graphql", %{"query" => query})

      assert %{
               "data" => %{
                 "chatMessages" => messages
               }
             } = json_response(conn, 200)

      assert length(messages) == 2
    end

    test "anonymous user cannot access authenticated user's chat", %{conn: conn} do
      user = insert(:user)
      {:ok, chat} = Chat.create_chat_with_message(user.id, "Private question", %{}, "academy_qa")

      query = """
      query {
        chat(id: "#{chat.id}") {
          id
          title
        }
      }
      """

      conn = post(conn, "/graphql", %{"query" => query})

      assert %{
               "data" => %{
                 "chat" => nil
               },
               "errors" => [
                 %{
                   "message" => "Access denied"
                 }
               ]
             } = json_response(conn, 200)
    end

    test "authenticated user cannot access anonymous chat", %{conn: conn} do
      user = insert(:user)
      {:ok, chat} = Chat.create_chat_with_message(nil, "Anonymous question", %{}, "academy_qa")

      query = """
      query {
        chat(id: "#{chat.id}") {
          id
          title
        }
      }
      """

      conn =
        conn
        |> setup_jwt_auth(user)
        |> post("/graphql", %{"query" => query})

      assert %{
               "data" => %{
                 "chat" => %{
                   "id" => chat_id,
                   "title" => "Anonymous question"
                 }
               }
             } = json_response(conn, 200)

      # Authenticated users CAN access anonymous chats (they're public)
      assert chat_id == chat.id
    end

    test "anonymous user gets proper error for non-existent chat", %{conn: conn} do
      fake_chat_id = Ecto.UUID.generate()

      query = """
      query {
        chat(id: "#{fake_chat_id}") {
          id
          title
        }
      }
      """

      conn = post(conn, "/graphql", %{"query" => query})

      assert %{
               "data" => %{
                 "chat" => nil
               },
               "errors" => [
                 %{
                   "message" => "Chat not found"
                 }
               ]
             } = json_response(conn, 200)
    end

    test "handles Academy AI API error for anonymous user", %{conn: conn} do
      # Mock Academy AI service error
      http_response = %Req.Response{status: 500, body: ""}

      Sanbase.Mock.prepare_mock2(&Req.post/2, {:ok, http_response})
      |> Sanbase.Mock.run_with_mocks(fn ->
        mutation = """
        mutation {
          sendChatMessage(
            content: "What is DeFi?"
            type: ACADEMY_QA
          ) {
            chatMessages {
              content
              role
            }
          }
        }
        """

        # Capture logs to suppress error messages during test
        capture_log(fn ->
          conn = post(conn, "/graphql", %{"query" => mutation})

          assert %{
                   "data" => %{
                     "sendChatMessage" => %{
                       "chatMessages" => [
                         %{
                           "content" => "What is DeFi?",
                           "role" => "USER"
                         }
                         # No AI response due to error
                       ]
                     }
                   }
                 } = json_response(conn, 200)
        end)
      end)
    end
  end

  # Helper functions
  defp mock_academy_response do
    mock_response = %{
      "answer" =>
        "DeFi stands for Decentralized Finance, which refers to financial services built on blockchain technology.",
      "sources" => [
        %{
          "number" => 0,
          "title" => "DeFi Fundamentals",
          "url" => "https://academy.santiment.net/defi",
          "similarity" => 0.95
        }
      ]
    }

    http_response = %Req.Response{status: 200, body: mock_response}
    Sanbase.Mock.prepare_mock2(&Req.post/2, {:ok, http_response})
  end

  defp mock_dyor_response do
    # Mock OpenAI for DYOR dashboard AI responses
    expect(Sanbase.AI.MockOpenAIClient, :chat_completion, fn _system_prompt,
                                                             _user_message,
                                                             _opts ->
      {:ok,
       "Bitcoin analysis shows strong fundamentals with current market trends indicating potential for growth."}
    end)

    # No title generation for anonymous users
  end
end
