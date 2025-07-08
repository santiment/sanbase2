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
      user_id: user_id_string,
      include_suggestions: false
    }

    case make_academy_request(request_params) do
      {:ok, response} ->
        {:ok, extract_academy_response(response)}

      {:error, reason} ->
        Logger.error("Academy AI request failed: #{inspect(reason)}")
        {:error, "Failed to get Academy response"}
    end
  end

  @doc """
  Generates an Academy Q&A response for a standalone question (without chat context).

  Optionally includes suggestions for related questions.
  """
  @spec generate_standalone_response(String.t(), integer() | nil, boolean()) ::
          {:ok, map()} | {:error, String.t()}
  def generate_standalone_response(question, user_id \\ nil, include_suggestions \\ true) do
    user_id_string = if user_id, do: to_string(user_id), else: "anonymous"

    request_params = %{
      question: question,
      user_id: user_id_string,
      include_suggestions: include_suggestions
    }

    case make_academy_request(request_params) do
      {:ok, response} ->
        {:ok, extract_full_response(response)}

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

    case Req.post(url,
           json: params,
           headers: %{"accept" => "application/json"},
           receive_timeout: 30_000,
           connect_options: [timeout: 30_000]
         ) do
      {:ok, %Req.Response{status: 200, body: response_body}} ->
        {:ok, response_body}

      {:ok, %Req.Response{status: status}} ->
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

  defp extract_full_response(response) do
    %{
      answer: Map.get(response, "answer", ""),
      sources: Map.get(response, "sources", []),
      suggestions: Map.get(response, "suggestions", []),
      suggestions_confidence: Map.get(response, "suggestions_confidence", ""),
      confidence: Map.get(response, "confidence", ""),
      total_time_ms: Map.get(response, "total_time_ms", 0)
    }
  end

  defp ai_server_url do
    System.get_env("AI_SERVER_URL") || "http://aiserver.production.san:31080"
  end
end
