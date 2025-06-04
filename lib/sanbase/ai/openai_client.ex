defmodule Sanbase.AI.OpenAIClient do
  @moduledoc """
  OpenAI API client using Req for chat completions.
  """

  require Logger

  @base_url "https://api.openai.com/v1"
  @model "gpt-4.1-mini"

  @doc """
  Creates a chat completion using the OpenAI API.
  """
  @spec chat_completion(String.t(), String.t(), Keyword.t()) ::
          {:ok, String.t()} | {:error, String.t()}
  def chat_completion(system_prompt, user_message, opts \\ []) do
    model = Keyword.get(opts, :model, @model)
    max_tokens = Keyword.get(opts, :max_tokens, 1000)
    temperature = Keyword.get(opts, :temperature, 0.7)

    messages = [
      %{"role" => "system", "content" => system_prompt},
      %{"role" => "user", "content" => user_message}
    ]

    payload = %{
      model: model,
      messages: messages,
      max_tokens: max_tokens,
      temperature: temperature
    }

    headers = [
      {"authorization", "Bearer #{openai_api_key()}"},
      {"content-type", "application/json"}
    ]

    case Req.post("#{@base_url}/chat/completions", json: payload, headers: headers) do
      {:ok, %{status: 200, body: %{"choices" => [%{"message" => %{"content" => content}} | _]}}} ->
        {:ok, content}

      {:ok, %{status: status, body: body}} ->
        Logger.error("OpenAI API error: status #{status}, body: #{inspect(body)}")
        {:error, "OpenAI API error: #{status}"}

      {:error, error} ->
        Logger.error("OpenAI API request failed: #{inspect(error)}")
        {:error, "OpenAI API request failed"}
    end
  end

  @doc """
  Generates a chat title based on the first user message.
  """
  @spec generate_chat_title(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def generate_chat_title(first_message) do
    system_prompt = """
    You are a helpful assistant that creates concise, descriptive titles for chat conversations.
    Based on the user's first message, generate a short title (maximum 50 characters) that captures the essence of their question or request.
    Return only the title, no additional text or formatting.
    """

    user_prompt = """
    Create a title for a chat that starts with this message:
    "#{first_message}"
    """

    case chat_completion(system_prompt, user_prompt, max_tokens: 20, temperature: 0.3) do
      {:ok, title} ->
        title = title |> String.trim() |> String.slice(0, 50)
        {:ok, title}

      {:error, error} ->
        {:error, error}
    end
  end

  defp openai_api_key do
    System.get_env("OPENAI_API_KEY") ||
      raise "OPENAI_API_KEY environment variable is not set"
  end
end
