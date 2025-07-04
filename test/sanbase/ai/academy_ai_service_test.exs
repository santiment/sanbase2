defmodule Sanbase.AI.AcademyAIServiceTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import Mox

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

      # Mock HTTPoison.post to simulate aiserver response
      http_response = %HTTPoison.Response{status_code: 200, body: Jason.encode!(mock_response)}

      Sanbase.Mock.prepare_mock2(&HTTPoison.post/4, {:ok, http_response})
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
      question = "What is blockchain?"

      mock_response = %{
        "answer" =>
          "Blockchain is a distributed ledger technology that maintains a continuously growing list of records.",
        "sources" => []
      }

      http_response = %HTTPoison.Response{status_code: 200, body: Jason.encode!(mock_response)}

      Sanbase.Mock.prepare_mock2(&HTTPoison.post/4, {:ok, http_response})
      |> Sanbase.Mock.run_with_mocks(fn ->
        message_id = Ecto.UUID.generate()

        assert {:ok, response} =
                 AcademyAIService.generate_academy_response(question, chat.id, message_id, nil)

        expected_answer =
          "Blockchain is a distributed ledger technology that maintains a continuously growing list of records."

        assert response == %{answer: expected_answer, sources: []}
      end)
    end

    test "handles response with sources without URLs", %{user: user, chat: chat} do
      question = "What is staking?"

      mock_response = %{
        "answer" =>
          "Staking is the process of participating in the validation of transactions on a proof-of-stake blockchain.",
        "sources" => [
          %{
            "number" => 0,
            "title" => "Staking Basics",
            "url" => "",
            "similarity" => 0.88
          }
        ]
      }

      http_response = %HTTPoison.Response{status_code: 200, body: Jason.encode!(mock_response)}

      Sanbase.Mock.prepare_mock2(&HTTPoison.post/4, {:ok, http_response})
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
          "Staking is the process of participating in the validation of transactions on a proof-of-stake blockchain."

        expected_sources = [
          %{
            "number" => 0,
            "title" => "Staking Basics",
            "url" => "",
            "similarity" => 0.88
          }
        ]

        assert response == %{answer: expected_answer, sources: expected_sources}
      end)
    end

    test "handles API error response", %{user: user, chat: chat} do
      question = "What is NFT?"

      http_response = %HTTPoison.Response{status_code: 500, body: ""}

      Sanbase.Mock.prepare_mock2(&HTTPoison.post/4, {:ok, http_response})
      |> Sanbase.Mock.run_with_mocks(fn ->
        message_id = Ecto.UUID.generate()

        assert {:error, "Failed to get Academy response"} =
                 AcademyAIService.generate_academy_response(
                   question,
                   chat.id,
                   message_id,
                   user.id
                 )
      end)
    end

    test "handles network error", %{user: user, chat: chat} do
      question = "What is DAO?"

      Sanbase.Mock.prepare_mock2(&HTTPoison.post/4, {:error, %HTTPoison.Error{reason: :timeout}})
      |> Sanbase.Mock.run_with_mocks(fn ->
        message_id = Ecto.UUID.generate()

        assert {:error, "Failed to get Academy response"} =
                 AcademyAIService.generate_academy_response(
                   question,
                   chat.id,
                   message_id,
                   user.id
                 )
      end)
    end

    test "handles empty chat (no history)", %{user: user} do
      {:ok, empty_chat} =
        Chat.create_chat(%{
          title: "Empty Chat",
          user_id: user.id,
          type: "academy_qa"
        })

      question = "What is cryptocurrency?"

      mock_response = %{
        "answer" => "Cryptocurrency is a digital or virtual currency secured by cryptography.",
        "sources" => []
      }

      http_response = %HTTPoison.Response{status_code: 200, body: Jason.encode!(mock_response)}

      Sanbase.Mock.prepare_mock2(&HTTPoison.post/4, {:ok, http_response})
      |> Sanbase.Mock.run_with_mocks(fn ->
        message_id = Ecto.UUID.generate()

        assert {:ok, response} =
                 AcademyAIService.generate_academy_response(
                   question,
                   empty_chat.id,
                   message_id,
                   user.id
                 )

        expected_answer =
          "Cryptocurrency is a digital or virtual currency secured by cryptography."

        assert response == %{answer: expected_answer, sources: []}
      end)
    end

    test "builds correct chat history format", %{user: user, chat: chat} do
      question = "Tell me more about smart contracts"

      mock_response = %{
        "answer" => "Smart contracts are self-executing contracts.",
        "sources" => []
      }

      http_response = %HTTPoison.Response{status_code: 200, body: Jason.encode!(mock_response)}

      Sanbase.Mock.prepare_mock2(&HTTPoison.post/4, {:ok, http_response})
      |> Sanbase.Mock.run_with_mocks(fn ->
        message_id = Ecto.UUID.generate()

        assert {:ok, response} =
                 AcademyAIService.generate_academy_response(
                   question,
                   chat.id,
                   message_id,
                   user.id
                 )

        expected_answer = "Smart contracts are self-executing contracts."
        assert response == %{answer: expected_answer, sources: []}
      end)
    end
  end
end
