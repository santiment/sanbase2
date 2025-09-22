defmodule Sanbase.AI.AcademyAIService do
  @moduledoc """
  Service for generating Academy Q&A responses using the aiserver API.
  Handles both registered and unregistered users.
  """

  require Logger
  alias Sanbase.Knowledge.Faq

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

  @doc """
  Search Academy using the simple query endpoint and return a list of maps
  with keys: `:title`, `:chunk`, and `:score`.
  """
  @spec search_academy_simple(String.t(), non_neg_integer()) ::
          {:ok, list(map())} | {:error, String.t()}
  def search_academy_simple(question, top_k \\ 5)
      when is_binary(question) and is_integer(top_k) and top_k >= 0 do
    url = "#{ai_server_url()}/academy/query-simple"

    case Req.post(url,
           json: %{question: question, top_k: top_k},
           headers: %{"accept" => "application/json"},
           receive_timeout: 30_000,
           connect_options: [timeout: 30_000]
         ) do
      {:ok, %Req.Response{status: 200, body: %{"results" => results}}} when is_list(results) ->
        items =
          Enum.map(results, fn item ->
            %{
              title: Map.get(item, "title"),
              text_chunk: Map.get(item, "chunk"),
              similarity: Map.get(item, "similarity") || Map.get(item, "score")
            }
          end)

        {:ok, items}

      {:ok, %Req.Response{status: status}} ->
        Logger.error("Academy simple query API error: status #{status}")
        {:error, "Academy search unavailable"}

      {:error, error} ->
        Logger.error("Academy simple query request failed: #{inspect(error)}")
        {:error, "Failed to search Academy"}
    end
  end

  @doc """
  Search across Academy and FAQ entries and return a combined list of
  maps with keys: `:source`, `:title` (FAQ question is mapped to title), and `:score`.
  """
  @spec search_docs(String.t(), non_neg_integer()) :: {:ok, list(map())} | {:error, String.t()}
  def search_docs(question, top_k \\ 5)
      when is_binary(question) and is_integer(top_k) and top_k >= 0 do
    academy_res = search_academy_simple(question, top_k)
    faq_res = Faq.find_most_similar_faqs(question, top_k)

    academy_items =
      case academy_res do
        {:ok, items} when is_list(items) ->
          Enum.map(items, fn item ->
            %{
              source: "academy",
              title: Map.get(item, :title) || Map.get(item, "title"),
              score: Map.get(item, :score) || Map.get(item, "score"),
              chunk: Map.get(item, :chunk) || Map.get(item, "chunk")
            }
          end)

        _ ->
          []
      end

    faq_items =
      case faq_res do
        {:ok, items} when is_list(items) ->
          Enum.map(items, fn item ->
            %{
              source: "faq",
              title: Map.get(item, :question),
              score: Map.get(item, :similarity),
              chunk: Map.get(item, :answer_markdown)
            }
          end)

        _ ->
          []
      end

    combined = academy_items ++ faq_items
    combined_sorted = Enum.sort_by(combined, &(&1.score || 0), :desc)
    combined_limited = if top_k > 0, do: Enum.take(combined_sorted, top_k), else: combined_sorted

    cond do
      combined_limited != [] ->
        {:ok, combined_limited}

      match?({:error, _}, academy_res) and match?({:error, _}, faq_res) ->
        {:error, "No results: both Academy and FAQ searches failed"}

      true ->
        {:ok, []}
    end
  end

  @doc """
  Get autocomplete question suggestions for Academy Q&A based on a query string.

  Returns a list of suggested questions with their titles.
  """
  @spec autocomplete_questions(String.t()) :: {:ok, list()} | {:error, String.t()}
  def autocomplete_questions(query) do
    url = "#{ai_server_url()}/academy/autocomplete-questions"

    case Req.post(url,
           json: %{query: query},
           headers: %{"Content-Type" => "application/json"},
           receive_timeout: 10_000,
           connect_options: [timeout: 10_000]
         ) do
      {:ok, %Req.Response{status: 200, body: suggestions}} when is_list(suggestions) ->
        {:ok, suggestions}

      {:ok, %Req.Response{status: status}} ->
        Logger.error("Academy autocomplete API error: status #{status}")
        {:error, "Autocomplete service unavailable"}

      {:error, error} ->
        Logger.error("Academy autocomplete request failed: #{inspect(error)}")
        {:error, "Failed to get question suggestions"}
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
