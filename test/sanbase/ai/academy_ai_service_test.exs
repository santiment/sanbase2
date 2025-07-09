defmodule Sanbase.AI.AcademyAIServiceTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory
  import Mox
  import ExUnit.CaptureLog

  alias Sanbase.AI.AcademyAIService
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

  describe "generate_academy_response/4" do
    test "generates response with chat history", %{user: user, chat: chat} do
      question = "What are the risks of DeFi?"

      mock_response = %{
        "answer" =>
          "DeFi risks include smart contract vulnerabilities, liquidity risks, and regulatory uncertainties.",
        "confidence" => "high",
        "sources" => [
          %{
            "number" => 0,
            "title" => "DeFi Risk Assessment Guide",
            "url" => "https://academy.santiment.net/defi-risks",
            "similarity" => 0.95,
            "chunks_count" => 3
          }
        ],
        "chunks_used" => 3,
        "search_time_ms" => 150,
        "generation_time_ms" => 800,
        "total_time_ms" => 950
      }

      # Mock Req.post using prepare_mock2
      http_response = %Req.Response{status: 200, body: mock_response}

      Sanbase.Mock.prepare_mock2(&Req.post/2, {:ok, http_response})
      |> Sanbase.Mock.run_with_mocks(fn ->
        message_id = Ecto.UUID.generate()

        assert {:ok, response} =
                 AcademyAIService.generate_academy_response(
                   question,
                   chat.id,
                   message_id,
                   user.id
                 )

        expected_answer =
          "DeFi risks include smart contract vulnerabilities, liquidity risks, and regulatory uncertainties."

        expected_sources = [
          %{
            "number" => 0,
            "title" => "DeFi Risk Assessment Guide",
            "url" => "https://academy.santiment.net/defi-risks",
            "similarity" => 0.95,
            "chunks_count" => 3
          }
        ]

        assert response == %{answer: expected_answer, sources: expected_sources}
      end)
    end

    test "generates response for anonymous user", %{chat: chat} do
      question = "What is Santiment?"

      mock_response = %{
        "answer" => "Santiment is a crypto analytics platform.",
        "confidence" => "high",
        "sources" => []
      }

      http_response = %Req.Response{status: 200, body: mock_response}

      Sanbase.Mock.prepare_mock2(&Req.post/2, {:ok, http_response})
      |> Sanbase.Mock.run_with_mocks(fn ->
        message_id = Ecto.UUID.generate()

        assert {:ok, response} =
                 AcademyAIService.generate_academy_response(
                   question,
                   chat.id,
                   message_id,
                   nil
                 )

        assert response == %{answer: "Santiment is a crypto analytics platform.", sources: []}
      end)
    end

    test "handles response with sources without URLs", %{user: user, chat: chat} do
      question = "What is DeFi?"

      mock_response = %{
        "answer" => "DeFi stands for decentralized finance.",
        "confidence" => "medium",
        "sources" => [
          %{
            "number" => 0,
            "title" => "DeFi Introduction",
            "similarity" => 0.88
          }
        ]
      }

      http_response = %Req.Response{status: 200, body: mock_response}

      Sanbase.Mock.prepare_mock2(&Req.post/2, {:ok, http_response})
      |> Sanbase.Mock.run_with_mocks(fn ->
        message_id = Ecto.UUID.generate()

        assert {:ok, response} =
                 AcademyAIService.generate_academy_response(
                   question,
                   chat.id,
                   message_id,
                   user.id
                 )

        expected_sources = [
          %{
            "number" => 0,
            "title" => "DeFi Introduction",
            "similarity" => 0.88
          }
        ]

        assert response == %{
                 answer: "DeFi stands for decentralized finance.",
                 sources: expected_sources
               }
      end)
    end

    test "handles API error response", %{user: user, chat: chat} do
      http_response = %Req.Response{status: 500, body: %{}}

      Sanbase.Mock.prepare_mock2(&Req.post/2, {:ok, http_response})
      |> Sanbase.Mock.run_with_mocks(fn ->
        message_id = Ecto.UUID.generate()

        # Capture logs to suppress error messages during test
        capture_log(fn ->
          assert {:error, error} =
                   AcademyAIService.generate_academy_response(
                     "What is DeFi?",
                     chat.id,
                     message_id,
                     user.id
                   )

          assert error == "Failed to get Academy response"
        end)
      end)
    end

    test "handles network error", %{user: user, chat: chat} do
      Sanbase.Mock.prepare_mock2(&Req.post/2, {:error, %Req.TransportError{reason: :timeout}})
      |> Sanbase.Mock.run_with_mocks(fn ->
        message_id = Ecto.UUID.generate()

        # Capture logs to suppress error messages during test
        capture_log(fn ->
          assert {:error, error} =
                   AcademyAIService.generate_academy_response(
                     "What is DeFi?",
                     chat.id,
                     message_id,
                     user.id
                   )

          assert error == "Failed to get Academy response"
        end)
      end)
    end

    test "handles empty chat (no history)", %{user: user} do
      # Create a new chat with no messages
      {:ok, empty_chat} = Chat.create_chat(%{title: "Empty Chat"})

      mock_response = %{
        "answer" => "This is a response without chat history.",
        "confidence" => "high",
        "sources" => []
      }

      http_response = %Req.Response{status: 200, body: mock_response}

      Sanbase.Mock.prepare_mock2(&Req.post/2, {:ok, http_response})
      |> Sanbase.Mock.run_with_mocks(fn ->
        message_id = Ecto.UUID.generate()

        assert {:ok, response} =
                 AcademyAIService.generate_academy_response(
                   "What is blockchain?",
                   empty_chat.id,
                   message_id,
                   user.id
                 )

        assert response == %{
                 answer: "This is a response without chat history.",
                 sources: []
               }
      end)
    end

    test "builds correct chat history format", %{user: user, chat: chat} do
      question = "Tell me more about crypto trading"

      mock_response = %{
        "answer" => "Crypto trading involves buying and selling cryptocurrencies.",
        "confidence" => "high",
        "sources" => []
      }

      http_response = %Req.Response{status: 200, body: mock_response}

      Sanbase.Mock.prepare_mock2(&Req.post/2, {:ok, http_response})
      |> Sanbase.Mock.run_with_mocks(fn ->
        message_id = Ecto.UUID.generate()

        assert {:ok, response} =
                 AcademyAIService.generate_academy_response(
                   question,
                   chat.id,
                   message_id,
                   user.id
                 )

        assert response.answer == "Crypto trading involves buying and selling cryptocurrencies."
      end)
    end
  end

  describe "generate_standalone_response/3" do
    test "generates response with suggestions for standalone question" do
      question = "What are the key DeFi metrics to track?"

      mock_response = %{
        "answer" => "Key DeFi metrics include TVL, volume, and active addresses.",
        "confidence" => "high",
        "sources" => [
          %{
            "number" => 0,
            "title" => "DeFi Metrics Guide",
            "url" => "https://academy.santiment.net/defi-metrics",
            "similarity" => 0.92
          }
        ],
        "suggestions" => [
          "How to calculate Total Value Locked (TVL)?",
          "What is the significance of trading volume in DeFi?",
          "How do active addresses indicate DeFi adoption?"
        ],
        "suggestions_confidence" => "high",
        "total_time_ms" => 1250
      }

      http_response = %Req.Response{status: 200, body: mock_response}

      Sanbase.Mock.prepare_mock2(&Req.post/2, {:ok, http_response})
      |> Sanbase.Mock.run_with_mocks(fn ->
        assert {:ok, response} =
                 AcademyAIService.generate_standalone_response(question, nil, true)

        assert response.answer == "Key DeFi metrics include TVL, volume, and active addresses."
        assert response.confidence == "high"
        assert response.suggestions_confidence == "high"
        assert length(response.suggestions) == 3
        assert response.total_time_ms == 1250

        assert Enum.member?(response.suggestions, "How to calculate Total Value Locked (TVL)?")

        assert Enum.member?(
                 response.suggestions,
                 "What is the significance of trading volume in DeFi?"
               )

        assert Enum.member?(
                 response.suggestions,
                 "How do active addresses indicate DeFi adoption?"
               )
      end)
    end

    test "generates response without suggestions when disabled" do
      question = "What is yield farming?"

      mock_response = %{
        "answer" => "Yield farming involves lending crypto assets to earn rewards.",
        "confidence" => "medium",
        "sources" => [],
        "total_time_ms" => 800
      }

      http_response = %Req.Response{status: 200, body: mock_response}

      Sanbase.Mock.prepare_mock2(&Req.post/2, {:ok, http_response})
      |> Sanbase.Mock.run_with_mocks(fn ->
        assert {:ok, response} =
                 AcademyAIService.generate_standalone_response(question, nil, false)

        assert response.answer == "Yield farming involves lending crypto assets to earn rewards."
        assert response.confidence == "medium"
        assert response.suggestions == []
        assert response.suggestions_confidence == ""
        assert response.total_time_ms == 800
      end)
    end

    test "handles standalone API error" do
      http_response = %Req.Response{status: 500, body: %{}}

      Sanbase.Mock.prepare_mock2(&Req.post/2, {:ok, http_response})
      |> Sanbase.Mock.run_with_mocks(fn ->
        # Capture logs to suppress error messages during test
        capture_log(fn ->
          assert {:error, error} =
                   AcademyAIService.generate_standalone_response("What is DeFi?", nil, true)

          assert error == "Failed to get Academy response"
        end)
      end)
    end

    test "handles network error for standalone request" do
      Sanbase.Mock.prepare_mock2(&Req.post/2, {:error, %Req.TransportError{reason: :timeout}})
      |> Sanbase.Mock.run_with_mocks(fn ->
        # Capture logs to suppress error messages during test
        capture_log(fn ->
          assert {:error, error} =
                   AcademyAIService.generate_standalone_response("What is DeFi?", nil, true)

          assert error == "Failed to get Academy response"
        end)
      end)
    end
  end
end
