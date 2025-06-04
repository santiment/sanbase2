defmodule Sanbase.AI.ChatAIServiceTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import Mock

  alias Sanbase.AI.{ChatAIService, OpenAIClient}
  alias Sanbase.Chat
  alias Sanbase.Dashboards
  alias Sanbase.Queries

  setup do
    user = insert(:user)

    # Create a test dashboard with queries
    {:ok, dashboard} =
      Dashboards.create_dashboard(
        %{
          name: "Crypto Analysis Dashboard",
          description: "Dashboard for analyzing Bitcoin metrics",
          is_public: false
        },
        user.id
      )

    {:ok, query} =
      Queries.create_query(
        %{
          name: "Bitcoin Price Query",
          description: "Get Bitcoin price data",
          sql_query_text:
            "SELECT * FROM metrics WHERE asset = 'bitcoin' AND metric = 'price_usd'",
          sql_query_parameters: %{"limit" => 100}
        },
        user.id
      )

    {:ok, _mapping} = Dashboards.add_query_to_dashboard(dashboard.id, query.id, user.id)

    {:ok, chat} =
      Chat.create_chat(%{
        title: "Test Chat",
        user_id: user.id,
        type: "dyor_dashboard"
      })

    %{
      user: user,
      dashboard: dashboard,
      query: query,
      chat: chat
    }
  end

  describe "generate_ai_response/4" do
    test "generates response with dashboard context", %{
      user: user,
      dashboard: dashboard,
      chat: chat
    } do
      user_message = "What can you tell me about Bitcoin's price trends?"

      context = %{
        "dashboard_id" => dashboard.id,
        "asset" => "bitcoin",
        "metrics" => ["price_usd"]
      }

      mock_response =
        "Based on the Bitcoin Price Query in your Crypto Analysis Dashboard, I can see that..."

      with_mock OpenAIClient,
        chat_completion: fn _system_prompt, _user_message, _opts ->
          {:ok, mock_response}
        end do
        assert {:ok, response} =
                 ChatAIService.generate_ai_response(
                   user_message,
                   context,
                   chat.id,
                   user.id
                 )

        assert response == mock_response

        # Verify that the OpenAI client was called with appropriate system prompt
        assert_called(OpenAIClient.chat_completion(:_, :_, :_))
      end
    end

    test "generates generic response when no dashboard context", %{user: user, chat: chat} do
      user_message = "What is blockchain?"
      context = %{}

      mock_response = "Blockchain is a distributed ledger technology..."

      with_mock OpenAIClient,
        chat_completion: fn _system_prompt, _user_message, _opts ->
          {:ok, mock_response}
        end do
        assert {:ok, response} =
                 ChatAIService.generate_ai_response(
                   user_message,
                   context,
                   chat.id,
                   user.id
                 )

        assert response == mock_response
      end
    end

    test "handles invalid dashboard_id", %{user: user, chat: chat} do
      user_message = "Test message"
      context = %{"dashboard_id" => "invalid"}

      # When dashboard_id is invalid format, it should return an error
      assert {:error, "Invalid dashboard_id format"} =
               ChatAIService.generate_ai_response(
                 user_message,
                 context,
                 chat.id,
                 user.id
               )
    end

    test "handles dashboard access errors", %{user: user, chat: chat} do
      other_user = insert(:user)

      {:ok, private_dashboard} =
        Dashboards.create_dashboard(
          %{
            name: "Private Dashboard",
            is_public: false
          },
          other_user.id
        )

      user_message = "Test message"
      context = %{"dashboard_id" => private_dashboard.id}

      mock_response = "Generic response due to access error"

      with_mock OpenAIClient,
        chat_completion: fn _system_prompt, _user_message, _opts ->
          {:ok, mock_response}
        end do
        assert {:ok, response} =
                 ChatAIService.generate_ai_response(
                   user_message,
                   context,
                   chat.id,
                   user.id
                 )

        assert response == mock_response
      end
    end
  end

  describe "generate_and_update_chat_title/2" do
    test "generates and updates chat title", %{chat: chat} do
      first_message = "What are the key metrics for Bitcoin analysis?"
      mock_title = "Bitcoin Analysis Metrics"

      with_mock OpenAIClient,
        generate_chat_title: fn _message ->
          {:ok, mock_title}
        end do
        assert :ok = ChatAIService.generate_and_update_chat_title(chat.id, first_message)

        # Give the async task time to complete
        Process.sleep(100)

        # Verify the chat title was updated
        updated_chat = Chat.get_chat(chat.id)
        assert updated_chat.title == mock_title

        assert_called(OpenAIClient.generate_chat_title(first_message))
      end
    end

    test "handles title generation errors gracefully", %{chat: chat} do
      first_message = "Test message"

      with_mock OpenAIClient,
        generate_chat_title: fn _message ->
          {:error, "API error"}
        end do
        assert :ok = ChatAIService.generate_and_update_chat_title(chat.id, first_message)

        # Give the async task time to complete
        Process.sleep(100)

        # Chat title should remain unchanged
        updated_chat = Chat.get_chat(chat.id)
        assert updated_chat.title == "Test Chat"
      end
    end
  end
end
