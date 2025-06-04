defmodule Sanbase.AI.ChatAIServiceTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import Mox

  alias Sanbase.AI.ChatAIService
  alias Sanbase.Chat
  alias Sanbase.Dashboards
  alias Sanbase.Queries

  setup :verify_on_exit!

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

      expect(Sanbase.AI.MockOpenAIClient, :chat_completion, fn system_prompt, user_msg, _opts ->
        # Verify the system prompt contains dashboard information
        assert String.contains?(system_prompt, "Crypto Analysis Dashboard")
        assert String.contains?(system_prompt, "Bitcoin Price Query")
        assert user_msg == user_message

        {:ok, mock_response}
      end)

      assert {:ok, response} =
               ChatAIService.generate_ai_response(
                 user_message,
                 context,
                 chat.id,
                 user.id
               )

      assert response == mock_response
    end

    test "generates generic response when no dashboard context", %{user: user, chat: chat} do
      user_message = "What is blockchain?"
      context = %{}

      mock_response = "Blockchain is a distributed ledger technology..."

      expect(Sanbase.AI.MockOpenAIClient, :chat_completion, fn system_prompt, user_msg, _opts ->
        # Verify it's using the generic system prompt
        assert String.contains?(
                 system_prompt,
                 "cryptocurrency data analysis and investment research"
               )

        assert user_msg == user_message

        {:ok, mock_response}
      end)

      assert {:ok, response} =
               ChatAIService.generate_ai_response(
                 user_message,
                 context,
                 chat.id,
                 user.id
               )

      assert response == mock_response
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

      expect(Sanbase.AI.MockOpenAIClient, :chat_completion, fn system_prompt, user_msg, _opts ->
        # Should fall back to generic prompt when dashboard access fails
        assert String.contains?(
                 system_prompt,
                 "cryptocurrency data analysis and investment research"
               )

        assert user_msg == user_message

        {:ok, mock_response}
      end)

      assert {:ok, response} =
               ChatAIService.generate_ai_response(
                 user_message,
                 context,
                 chat.id,
                 user.id
               )

      assert response == mock_response
    end

    test "handles OpenAI API errors", %{user: user, chat: chat} do
      user_message = "Test message"
      context = %{}

      expect(Sanbase.AI.MockOpenAIClient, :chat_completion, fn _system_prompt, _user_msg, _opts ->
        {:error, "API rate limit exceeded"}
      end)

      assert {:error, "Failed to generate response: API rate limit exceeded"} =
               ChatAIService.generate_ai_response(
                 user_message,
                 context,
                 chat.id,
                 user.id
               )
    end
  end

  describe "generate_and_update_chat_title/2" do
    test "generates and updates chat title", %{chat: chat} do
      first_message = "What are the key metrics for Bitcoin analysis?"
      mock_title = "Bitcoin Analysis Metrics"

      expect(Sanbase.AI.MockOpenAIClient, :generate_chat_title, fn message ->
        assert message == first_message
        {:ok, mock_title}
      end)

      assert :ok = ChatAIService.generate_and_update_chat_title(chat.id, first_message)

      # Give the async task time to complete
      Process.sleep(100)

      # Verify the chat title was updated
      updated_chat = Chat.get_chat(chat.id)
      assert updated_chat.title == mock_title
    end

    test "handles title generation errors gracefully", %{chat: chat} do
      first_message = "Test message"

      expect(Sanbase.AI.MockOpenAIClient, :generate_chat_title, fn message ->
        assert message == first_message
        {:error, "API error"}
      end)

      assert :ok = ChatAIService.generate_and_update_chat_title(chat.id, first_message)

      # Give the async task time to complete
      Process.sleep(100)

      # Chat title should remain unchanged
      updated_chat = Chat.get_chat(chat.id)
      assert updated_chat.title == "Test Chat"
    end
  end

  describe "generate_and_update_chat_title_sync/2" do
    test "generates and updates chat title synchronously", %{chat: chat} do
      first_message = "What are the key metrics for Bitcoin analysis?"
      mock_title = "Bitcoin Analysis Metrics"

      expect(Sanbase.AI.MockOpenAIClient, :generate_chat_title, fn message ->
        assert message == first_message
        {:ok, mock_title}
      end)

      assert {:ok, updated_chat} =
               ChatAIService.generate_and_update_chat_title_sync(chat.id, first_message)

      # Verify the chat title was updated immediately
      assert updated_chat.title == mock_title

      # Verify in database too
      db_chat = Chat.get_chat(chat.id)
      assert db_chat.title == mock_title
    end

    test "handles title generation errors", %{chat: chat} do
      first_message = "Test message"

      expect(Sanbase.AI.MockOpenAIClient, :generate_chat_title, fn message ->
        assert message == first_message
        {:error, "API error"}
      end)

      assert {:error, "Failed to generate chat title: API error"} =
               ChatAIService.generate_and_update_chat_title_sync(chat.id, first_message)

      # Chat title should remain unchanged
      updated_chat = Chat.get_chat(chat.id)
      assert updated_chat.title == "Test Chat"
    end
  end
end
