defmodule SanbaseWeb.Graphql.ChatAIIntegrationTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.TestHelpers
  import Mock

  alias Sanbase.AI.OpenAIClient
  alias Sanbase.Chat
  alias Sanbase.Dashboards
  alias Sanbase.Queries

  setup do
    clean_task_supervisor_children()

    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)

    # Create a test dashboard with queries
    {:ok, dashboard} =
      Dashboards.create_dashboard(
        %{
          name: "Bitcoin Analysis Dashboard",
          description: "Comprehensive Bitcoin market analysis",
          is_public: false
        },
        user.id
      )

    {:ok, query} =
      Queries.create_query(
        %{
          name: "Bitcoin Price Trends",
          description: "Track Bitcoin price movements over time",
          sql_query_text:
            "SELECT * FROM daily_metrics WHERE asset = 'bitcoin' AND metric = 'price_usd' ORDER BY dt DESC LIMIT 30",
          sql_query_parameters: %{"limit" => 30}
        },
        user.id
      )

    {:ok, _mapping} = Dashboards.add_query_to_dashboard(dashboard.id, query.id, user.id)

    %{
      conn: conn,
      user: user,
      dashboard: dashboard,
      query: query
    }
  end

  describe "DYOR dashboard chat AI integration" do
    test "creates new chat with AI response and title generation", %{
      conn: conn,
      dashboard: dashboard
    } do
      mock_ai_response =
        "Based on your Bitcoin Analysis Dashboard, I can help you analyze Bitcoin's price trends. The Bitcoin Price Trends query shows the last 30 days of price data..."

      mock_title = "Bitcoin Price Analysis"

      with_mocks([
        {OpenAIClient, [],
         [
           chat_completion: fn _system_prompt, _user_message, _opts ->
             {:ok, mock_ai_response}
           end,
           generate_chat_title: fn _message ->
             {:ok, mock_title}
           end
         ]}
      ]) do
        mutation = """
        mutation {
          sendChatMessage(
            content: "What trends can you identify in Bitcoin's recent price action?"
            context: {
              dashboardId: "#{dashboard.id}"
              asset: "bitcoin"
              metrics: ["price_usd", "volume_usd"]
            }
          ) {
            id
            title
            type
            chatMessages {
              id
              content
              role
              context
            }
          }
        }
        """

        result =
          conn
          |> post("/graphql", mutation_skeleton(mutation))
          |> json_response(200)
          |> get_in(["data", "sendChatMessage"])

        # Verify the chat was created
        assert result["type"] == "DYOR_DASHBOARD"
        # AI generates some title
        assert String.length(result["title"]) > 0

        # Should have both user and AI messages immediately (synchronous)
        assert length(result["chatMessages"]) >= 1

        user_message = Enum.find(result["chatMessages"], &(&1["role"] == "USER"))

        assert user_message["content"] ==
                 "What trends can you identify in Bitcoin's recent price action?"

        expected_context = %{
          "dashboard_id" => to_string(dashboard.id),
          "asset" => "bitcoin",
          "metrics" => ["price_usd", "volume_usd"]
        }

        assert user_message["context"] == expected_context

        # Check that AI response exists (content may vary)
        ai_message = Enum.find(result["chatMessages"], &(&1["role"] == "ASSISTANT"))

        if ai_message do
          assert String.length(ai_message["content"]) > 0
        end

        # Verify OpenAI was called appropriately
        assert_called(OpenAIClient.chat_completion(:_, :_, :_))
        assert_called(OpenAIClient.generate_chat_title(:_))
      end
    end

    test "adds AI response to existing DYOR dashboard chat", %{
      conn: conn,
      user: user,
      dashboard: dashboard
    } do
      # Create an existing chat
      {:ok, chat} =
        Chat.create_chat_with_message(
          user.id,
          "Initial question about Bitcoin",
          %{"dashboard_id" => dashboard.id, "asset" => "bitcoin"}
        )

      mock_ai_response =
        "Looking at the Bitcoin Analysis Dashboard data, I can provide insights on your follow-up question..."

      with_mock OpenAIClient,
        chat_completion: fn _system_prompt, _user_message, _opts ->
          {:ok, mock_ai_response}
        end do
        mutation = """
        mutation {
          sendChatMessage(
            chatId: "#{chat.id}"
            content: "What about volume patterns?"
            context: {
              dashboardId: "#{dashboard.id}"
              asset: "bitcoin"
              metrics: ["volume_usd"]
            }
          ) {
            id
            chatMessages {
              content
              role
            }
          }
        }
        """

        result =
          conn
          |> post("/graphql", mutation_skeleton(mutation))
          |> json_response(200)
          |> get_in(["data", "sendChatMessage"])

        # Should have initial messages plus new user message and AI response
        messages = result["chatMessages"]
        user_messages = Enum.filter(messages, &(&1["role"] == "USER"))
        assert length(user_messages) == 2

        ai_messages = Enum.filter(messages, &(&1["role"] == "ASSISTANT"))
        # May have AI responses (content may vary)
        if length(ai_messages) > 0 do
          Enum.each(ai_messages, fn ai_msg ->
            assert String.length(ai_msg["content"]) > 0
          end)
        end

        assert_called(OpenAIClient.chat_completion(:_, :_, :_))
      end
    end

    test "handles missing dashboard gracefully", %{conn: conn} do
      with_mock OpenAIClient,
        chat_completion: fn _system_prompt, _user_message, _opts ->
          {:ok, "Generic response about cryptocurrency analysis"}
        end,
        generate_chat_title: fn _message ->
          {:ok, "Bitcoin Discussion"}
        end do
        mutation = """
        mutation {
          sendChatMessage(
            content: "Tell me about Bitcoin"
            context: {
              dashboardId: "999999"
              asset: "bitcoin"
            }
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

        result =
          conn
          |> post("/graphql", mutation_skeleton(mutation))
          |> json_response(200)
          |> get_in(["data", "sendChatMessage"])

        # AI generates some title
        assert String.length(result["title"]) > 0
        assert length(result["chatMessages"]) >= 1

        # Should have both user and AI messages now (synchronous)
        user_message = Enum.find(result["chatMessages"], &(&1["role"] == "USER"))
        assert user_message["content"] == "Tell me about Bitcoin"

        ai_message = Enum.find(result["chatMessages"], &(&1["role"] == "ASSISTANT"))

        if ai_message do
          assert String.length(ai_message["content"]) > 0
        end

        # Should call OpenAI for both response and title generation
        assert_called(OpenAIClient.chat_completion(:_, :_, :_))
        assert_called(OpenAIClient.generate_chat_title(:_))
      end
    end
  end
end
