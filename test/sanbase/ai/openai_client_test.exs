defmodule Sanbase.AI.OpenAIClientTest do
  use ExUnit.Case, async: false
  use SanbaseWeb.ConnCase

  import Mox

  alias Sanbase.AI.OpenAIClient

  setup :verify_on_exit!

  describe "behaviour integration tests using Mox" do
    test "mock client follows behaviour contract for chat completion" do
      stub(Sanbase.AI.MockOpenAIClient, :chat_completion, fn _system_prompt,
                                                             user_message,
                                                             _opts ->
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

      result = Sanbase.AI.MockOpenAIClient.chat_completion("system", "bitcoin price", [])
      assert {:ok, response} = result
      assert is_binary(response)
      assert String.contains?(String.downcase(response), "bitcoin")
    end

    test "mock client generates titles" do
      stub(Sanbase.AI.MockOpenAIClient, :generate_chat_title, fn first_message ->
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

      result = Sanbase.AI.MockOpenAIClient.generate_chat_title("What about bitcoin trends?")
      assert {:ok, title} = result
      assert is_binary(title)
      assert String.length(title) > 0
      assert title == "Bitcoin Analysis"
    end

    test "mock client handles generic messages" do
      stub(Sanbase.AI.MockOpenAIClient, :chat_completion, fn _system_prompt,
                                                             _user_message,
                                                             _opts ->
        {:ok,
         "Based on the available data, here are some insights for your cryptocurrency analysis."}
      end)

      result = Sanbase.AI.MockOpenAIClient.chat_completion("system", "generic question", [])
      assert {:ok, response} = result
      assert is_binary(response)
      assert String.contains?(response, "available data")
    end

    test "mock client generates generic titles" do
      stub(Sanbase.AI.MockOpenAIClient, :generate_chat_title, fn _first_message ->
        {:ok, "Crypto Discussion"}
      end)

      result = Sanbase.AI.MockOpenAIClient.generate_chat_title("Some random question")
      assert {:ok, title} = result
      assert title == "Crypto Discussion"
    end

    test "mock client handles ethereum messages" do
      stub(Sanbase.AI.MockOpenAIClient, :chat_completion, fn _system_prompt,
                                                             _user_message,
                                                             _opts ->
        {:ok, "Ethereum metrics indicate strong network activity and usage patterns."}
      end)

      result = Sanbase.AI.MockOpenAIClient.chat_completion("system", "ethereum analysis", [])
      assert {:ok, response} = result
      assert String.contains?(String.downcase(response), "ethereum")
    end

    test "mock client generates ethereum titles" do
      stub(Sanbase.AI.MockOpenAIClient, :generate_chat_title, fn _first_message ->
        {:ok, "Ethereum Discussion"}
      end)

      result = Sanbase.AI.MockOpenAIClient.generate_chat_title("What about ethereum?")
      assert {:ok, title} = result
      assert title == "Ethereum Discussion"
    end

    test "mock client handles price messages" do
      stub(Sanbase.AI.MockOpenAIClient, :chat_completion, fn _system_prompt,
                                                             _user_message,
                                                             _opts ->
        {:ok,
         "The price analysis shows several key trends worth monitoring for your investment research."}
      end)

      result = Sanbase.AI.MockOpenAIClient.chat_completion("system", "price trends", [])
      assert {:ok, response} = result
      assert String.contains?(String.downcase(response), "price")
    end

    test "mock client generates price titles" do
      stub(Sanbase.AI.MockOpenAIClient, :generate_chat_title, fn _first_message ->
        {:ok, "Price Analysis"}
      end)

      result = Sanbase.AI.MockOpenAIClient.generate_chat_title("What are the price trends?")
      assert {:ok, title} = result
      assert title == "Price Analysis"
    end
  end

  test "API key is configured in test environment" do
    # Verify that the API key is set in test environment to prevent runtime errors
    api_key = System.get_env("OPENAI_API_KEY")
    assert api_key != nil
    assert String.length(api_key) > 0
  end

  test "real OpenAI client implementation exists" do
    # Verify the real implementation exists and has the right functions
    # but don't call them to avoid API requests
    assert Code.ensure_loaded?(OpenAIClient)
    assert function_exported?(OpenAIClient, :chat_completion, 3)
    assert function_exported?(OpenAIClient, :generate_chat_title, 1)
  end
end
