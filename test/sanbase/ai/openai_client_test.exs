defmodule Sanbase.AI.OpenAIClientTest do
  use ExUnit.Case, async: false

  import Mock

  alias Sanbase.AI.OpenAIClient

  describe "chat_completion/3" do
    test "successful API call returns content" do
      mock_response = %{
        status: 200,
        body: %{
          "choices" => [
            %{
              "message" => %{
                "content" => "This is a test response"
              }
            }
          ]
        }
      }

      with_mock Req,
        post: fn _url, _opts ->
          {:ok, mock_response}
        end do
        result =
          OpenAIClient.chat_completion(
            "You are a helpful assistant",
            "What is AI?",
            max_tokens: 100
          )

        assert {:ok, "This is a test response"} = result
      end
    end

    test "API error returns error tuple" do
      mock_response = %{
        status: 400,
        body: %{"error" => %{"message" => "Bad request"}}
      }

      with_mock Req,
        post: fn _url, _opts ->
          {:ok, mock_response}
        end do
        result =
          OpenAIClient.chat_completion(
            "You are a helpful assistant",
            "What is AI?"
          )

        assert {:error, "OpenAI API error: 400"} = result
      end
    end

    test "network error returns error tuple" do
      with_mock Req,
        post: fn _url, _opts ->
          {:error, :timeout}
        end do
        result =
          OpenAIClient.chat_completion(
            "You are a helpful assistant",
            "What is AI?"
          )

        assert {:error, "OpenAI API request failed"} = result
      end
    end

    test "uses custom options" do
      mock_response = %{
        status: 200,
        body: %{
          "choices" => [
            %{
              "message" => %{
                "content" => "Custom response"
              }
            }
          ]
        }
      }

      with_mock Req,
        post: fn _url, opts ->
          # Verify that custom options are passed
          json_payload = opts[:json]
          assert json_payload.max_tokens == 500
          assert json_payload.temperature == 0.5
          assert json_payload.model == "gpt-4"

          {:ok, mock_response}
        end do
        result =
          OpenAIClient.chat_completion(
            "System prompt",
            "User message",
            model: "gpt-4",
            max_tokens: 500,
            temperature: 0.5
          )

        assert {:ok, "Custom response"} = result
      end
    end
  end

  describe "generate_chat_title/1" do
    test "generates title successfully" do
      mock_response = %{
        status: 200,
        body: %{
          "choices" => [
            %{
              "message" => %{
                "content" => "Bitcoin Price Analysis"
              }
            }
          ]
        }
      }

      with_mock Req,
        post: fn _url, _opts ->
          {:ok, mock_response}
        end do
        result = OpenAIClient.generate_chat_title("What is Bitcoin's current price?")

        assert {:ok, "Bitcoin Price Analysis"} = result
      end
    end

    test "truncates long titles" do
      long_title = String.duplicate("a", 60)

      mock_response = %{
        status: 200,
        body: %{
          "choices" => [
            %{
              "message" => %{
                "content" => long_title
              }
            }
          ]
        }
      }

      with_mock Req,
        post: fn _url, _opts ->
          {:ok, mock_response}
        end do
        result = OpenAIClient.generate_chat_title("Test message")

        assert {:ok, title} = result
        assert String.length(title) <= 50
      end
    end

    test "handles API errors" do
      with_mock Req,
        post: fn _url, _opts ->
          {:error, :timeout}
        end do
        result = OpenAIClient.generate_chat_title("Test message")

        assert {:error, "OpenAI API request failed"} = result
      end
    end
  end

  test "requires OPENAI_API_KEY environment variable" do
    # This test verifies that the function will raise if API key is missing
    # In a real test environment, the key should be mocked or set
    assert_raise RuntimeError, ~r/OPENAI_API_KEY/, fn ->
      # Temporarily unset the env var
      original_key = System.get_env("OPENAI_API_KEY")
      System.delete_env("OPENAI_API_KEY")

      try do
        send(self(), :call_function)
        OpenAIClient.chat_completion("test", "test")
      after
        # Restore the env var
        if original_key, do: System.put_env("OPENAI_API_KEY", original_key)
      end
    end
  end
end
