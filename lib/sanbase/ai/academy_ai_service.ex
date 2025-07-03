defmodule Sanbase.AI.AcademyAIService do
  @moduledoc """
  Service for generating Academy Q&A responses using the aiserver API.
  Handles both registered and unregistered users.
  """

  require Logger

  @doc """
  Generates an Academy Q&A response for a chat message.

  Takes the user question, builds chat history from the conversation,
  and calls the aiserver Academy API.

  Returns both the answer text and sources separately.
  """
  @spec generate_academy_response(String.t(), String.t(), String.t(), integer() | nil) ::
          {:ok, %{answer: String.t(), sources: list()}} | {:error, String.t()}
  def generate_academy_response(question, chat_id, message_id, user_id) do
    chat_history = build_chat_history(chat_id)
    user_id_string = if user_id, do: to_string(user_id), else: "anonymous"

    request_params = %{
      question: question,
      chat_id: chat_id,
      message_id: message_id,
      chat_history: chat_history,
      user_id: user_id_string
    }

    case make_academy_request(request_params) do
      {:ok, response} ->
        {:ok, extract_academy_response(response)}

      {:error, reason} ->
        Logger.error("Academy AI request failed: #{inspect(reason)}")
        {:error, "Failed to get Academy response"}
    end
  end

  defp build_chat_history(chat_id) do
    case Sanbase.Chat.get_chat_messages(chat_id, limit: 20) do
      messages when is_list(messages) ->
        messages
        |> Enum.map(fn message ->
          %{
            role: Atom.to_string(message.role),
            content: message.content
          }
        end)

      _ ->
        []
    end
  end

  defp make_academy_request(params) do
    url = "#{ai_server_url()}/academy/query"
    body = Jason.encode!(params)
    headers = [{"Content-Type", "application/json"}, {"accept", "application/json"}]

    case HTTPoison.post(url, body, headers, timeout: 30_000, recv_timeout: 30_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, decoded_response} -> {:ok, decoded_response}
          {:error, _} -> {:error, "Failed to parse response"}
        end

      {:ok, %HTTPoison.Response{status_code: status}} ->
        {:error, "Academy API error: status #{status}"}

      {:error, error} ->
        {:error, "Academy API request failed: #{inspect(error)}"}
    end
  end

  defp extract_academy_response(response) do
    answer = Map.get(response, "answer", "")
    sources = Map.get(response, "sources", [])

    %{
      answer: answer,
      sources: sources
    }
  end

  defp ai_server_url do
    System.get_env("AI_SERVER_URL") || "http://aiserver.production.san:31080"
  end
end
