defmodule Sanbase.AI.AcademyAIService do
  @moduledoc """
  Service for generating Academy Q&A responses using the aiserver API.
  Handles both registered and unregistered users.
  """

  require Logger
  alias Sanbase.Knowledge.{Academy, Faq}
  alias Sanbase.OpenAI.Question
  alias Sanbase.AI.AcademyTracing, as: Tracing

  @dont_know_answer "DK"
  @dont_know_message "This one's not in my shell of knowledge yet 🐢📚. I only know what's written in the Academy scrolls, you can rephrase and try again — or swim over to Discord to chat with the humans\n👉 Ask on Discord: https://discord.gg/GEPZtyap"
  @model "gpt-5-nano"
  @suggestions_model "gpt-5-nano"
  @similarity_threshold 0.5

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
  Generates an Academy Q&A response using local database and OpenAI.

  This is the new implementation that uses local academy articles instead of the AI server.
  Includes chat history, source tracking, and validated suggestions.

  Returns both the answer text, sources, and suggestions.
  """
  @spec generate_local_response(String.t(), String.t() | nil, integer() | nil, boolean()) ::
          {:ok, map()} | {:error, String.t()}
  def generate_local_response(
        question,
        chat_id \\ nil,
        user_id \\ nil,
        include_suggestions \\ true
      ) do
    session_id = Tracing.generate_session_id(chat_id, user_id)
    chat_history = if chat_id, do: build_chat_history(chat_id), else: []

    with {:ok, chunks} <- Academy.search_chunks(question, 10),
         {:ok, answer, sources} <-
           generate_answer(question, chunks, chat_history, user_id, session_id) do
      suggestions =
        if include_suggestions and answer != @dont_know_message do
          case generate_suggestions(question, answer, sources, user_id, session_id) do
            {:ok, suggestions} -> suggestions
            _error -> []
          end
        else
          []
        end

      {:ok, %{answer: answer, sources: sources, suggestions: suggestions}}
    else
      {:error, reason} ->
        Logger.error("Local Academy AI request failed: #{inspect(reason)}")
        {:error, "Failed to generate Academy response"}
    end
  end

  @doc """
  Search across Academy and FAQ entries and return a combined list of
  maps with keys: `:source`, `:title` (FAQ question is mapped to title), and `:score`.
  """
  @spec search_docs(String.t(), non_neg_integer()) :: {:ok, list(map())} | {:error, String.t()}
  def search_docs(question, top_k \\ 5)
      when is_binary(question) and is_integer(top_k) and top_k >= 0 do
    academy_res = Academy.search_chunks(question, top_k)
    faq_res = Faq.find_most_similar_faqs(question, top_k)

    academy_items =
      case academy_res do
        {:ok, items} when is_list(items) ->
          Enum.map(items, fn item ->
            %{
              source: "academy",
              title: Map.get(item, :title),
              score: Map.get(item, :similarity),
              chunk: Map.get(item, :chunk),
              url: Map.get(item, :url)
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
           receive_timeout: 120_000,
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

  defp generate_answer(question, chunks, chat_history, user_id, session_id) do
    prompt = build_answer_prompt(question, chunks, chat_history)

    tracing_opts =
      Tracing.answer_tracing_opts(question, length(chunks), user_id, session_id, @model)

    case Question.ask(prompt, tracing_opts) do
      {:ok, answer} ->
        if String.trim(answer) == @dont_know_answer do
          {:ok, @dont_know_message, []}
        else
          {updated_answer, sources} = extract_and_renumber_sources(answer, chunks)
          {:ok, updated_answer, sources}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_answer_prompt(question, chunks, chat_history) do
    context = build_context_from_chunks(chunks)
    history_context = build_history_context(chat_history)
    system_prompt = build_academy_system_prompt(context, history_context)

    "#{system_prompt}\n\nQuestion: #{question}"
  end

  defp build_academy_system_prompt(context, history_context) do
    """
    You are the Santiment Academy AI Assistant. Your role is to answer questions ONLY using information from the Santiment Academy knowledge base.

    # CRITICAL RULES:

    1. If the Academy content doesn't contain enough information to answer the question, respond: "DK"
    2. Use INLINE CITATIONS throughout your answer with [1], [2], [3] etc. that correspond to the numbered sources below


    FORMATTING REQUIREMENTS:
    - Use markdown formatting for your response
    - Use ## for main headings, ### for subheadings if needed
    - Use **bold** for important terms and *italic* for emphasis
    - Use `code formatting` for technical terms, URLs, or code snippets
    - Use proper markdown lists (- for bullets, 1. for numbered)
    - Include inline citations [1], [2], [3] throughout the text when referencing specific information
    - Do NOT include a References section - citations will be provided separately

    CITATION FORMAT EXAMPLE:
    SAN tokens are the native cryptocurrency of Santiment [1]. You can purchase them directly on the website [2] or swap ETH for SAN tokens [1]. Holding more than 1,000 SAN provides a 20% discount on pricing plans [3].

    NOTE: Do NOT include a "References" section in your response. The references will be provided separately via the API response sources field.

    Academy Content Sources:
    #{context}#{history_context}

    Answer the user's question using ONLY the Academy content above with proper markdown formatting and inline citations.
    """
  end

  defp build_context_from_chunks(chunks) do
    chunks
    |> Enum.with_index(1)
    |> Enum.map(fn {chunk, index} ->
      """
      [#{index}] Title: #{chunk.title}
      URL: #{chunk.url}
      #{if chunk.heading, do: "Section: #{chunk.heading}\n", else: ""}
      Content: #{chunk.chunk}
      """
    end)
    |> Enum.join("\n---\n")
  end

  defp build_history_context([]), do: ""

  defp build_history_context(history) do
    history_text =
      history
      |> Enum.take(-5)
      |> Enum.map(fn msg ->
        role = String.capitalize(msg.role)
        "#{role}: #{msg.content}"
      end)
      |> Enum.join("\n")

    "\n\nRecent conversation history:\n#{history_text}"
  end

  defp extract_and_renumber_sources(answer, chunks) do
    citation_numbers = extract_citation_numbers(answer)

    {sources, mapping} =
      chunks
      |> Enum.with_index(1)
      |> Enum.filter(fn {_chunk, index} -> index in citation_numbers end)
      |> Enum.reduce({[], %{}, %{}}, fn {chunk, original_index}, {acc, mapping, seen_urls} ->
        if Map.has_key?(seen_urls, chunk.url) do
          existing_number = seen_urls[chunk.url]
          {acc, Map.put(mapping, original_index, existing_number), seen_urls}
        else
          new_number = length(acc) + 1

          source = %{
            "number" => new_number,
            "title" => chunk.title,
            "url" => chunk.url,
            "similarity" => chunk.similarity
          }

          {acc ++ [source], Map.put(mapping, original_index, new_number),
           Map.put(seen_urls, chunk.url, new_number)}
        end
      end)
      |> then(fn {sources, mapping, _seen_urls} -> {sources, mapping} end)

    updated_answer = renumber_citations_in_answer(answer, mapping)

    {updated_answer, sources}
  end

  defp extract_citation_numbers(answer) do
    Regex.scan(~r/\[(\d+)\]/, answer)
    |> Enum.map(fn [_, num] -> String.to_integer(num) end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp renumber_citations_in_answer(answer, mapping) do
    Regex.replace(~r/\[(\d+)\]/, answer, fn _, num_str ->
      original_num = String.to_integer(num_str)

      case Map.get(mapping, original_num) do
        nil -> "[#{num_str}]"
        new_num -> "[#{new_num}]"
      end
    end)
  end

  defp generate_suggestions(question, answer, sources, user_id, session_id) do
    tracing_opts =
      Tracing.suggestions_tracing_opts(question, user_id, session_id, @suggestions_model)

    with {:ok, trace_id} <- Tracing.create_suggestions_trace(question, answer, tracing_opts),
         {:ok, raw_suggestions} <-
           call_suggestions_llm(question, answer, sources, trace_id, tracing_opts),
         {validated, validation_details} <- validate_suggestions(raw_suggestions) do
      Tracing.log_validation_event(
        trace_id,
        session_id,
        user_id,
        question,
        raw_suggestions,
        validated,
        validation_details,
        @similarity_threshold
      )

      {:ok, validated}
    end
  end

  defp call_suggestions_llm(question, answer, sources, trace_id, tracing_opts) do
    {:ok, broader_chunks} = Academy.search_chunks(question, 5)

    prompt = build_suggestions_prompt(question, answer, sources, broader_chunks)
    tracing_opts_with_trace_id = Map.put(tracing_opts, :trace_id, trace_id)

    case Question.ask(prompt, tracing_opts_with_trace_id) do
      {:ok, response} ->
        case Jason.decode(response) do
          {:ok, suggestions} when is_list(suggestions) ->
            {:ok, Enum.take(suggestions, 5)}

          _ ->
            Logger.warning("Failed to parse suggestions JSON")
            {:ok, []}
        end

      {:error, reason} ->
        Logger.error("Failed to generate suggestions: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp build_suggestions_prompt(question, answer, sources, broader_chunks) do
    sources_context = build_sources_context(sources)
    broader_context = build_broader_context(broader_chunks)
    build_suggestions_system_prompt(sources_context, broader_context, question, answer)
  end

  defp build_sources_context([]), do: ""

  defp build_sources_context(sources) do
    sources_text =
      sources
      |> Enum.map(fn source ->
        "- #{source["title"]} (#{source["url"]})"
      end)
      |> Enum.join("\n")

    "Sources used in previous answer:\n#{sources_text}\n"
  end

  defp build_broader_context([]), do: ""

  defp build_broader_context(chunks) do
    broader_text =
      chunks
      |> Enum.map(fn chunk ->
        "- #{chunk.title}: #{String.slice(chunk.chunk, 0, 150)}..."
      end)
      |> Enum.join("\n")

    "\nAdditional Academy topics available:\n#{broader_text}"
  end

  defp build_suggestions_system_prompt(sources_context, broader_context, question, answer) do
    """
    You are the Santiment Academy AI Assistant. Your task is to generate 3-5 follow-up questions that:

    1. Are naturally related to the current conversation topic
    2. Can be answered using Santiment Academy knowledge base content
    3. Would help users dive deeper into the subject
    4. Are specific and actionable (not too broad or vague)

    GUIDELINES:
    - Generate questions that build upon the current answer
    - Focus on practical applications, features, tutorials, or related concepts
    - Ensure questions are about Santiment products, features, SAN tokens, API usage, or crypto analysis
    - Avoid questions that require external information not in Academy
    - Make questions conversational and engaging
    - Vary the question types (how-to, what-is, best-practices, etc.)

    FORMAT: Return ONLY a JSON array of strings, nothing else. Example:
    ["How do I configure API rate limits in Sanbase?", "What are the benefits of holding SAN tokens?", "How can I export data from Sanbase?"]

    CONTEXT:
    #{sources_context}#{broader_context}

    Previous Q&A:
    Question: #{question}
    Answer: #{answer}
    """
  end

  defp validate_suggestions(suggestions) do
    results =
      suggestions
      |> Task.async_stream(
        fn suggestion ->
          case Academy.search_chunks(suggestion, 3) do
            {:ok, chunks} ->
              max_similarity = chunks |> Enum.map(& &1.similarity) |> Enum.max(fn -> 0.0 end)

              has_good_match =
                Enum.any?(chunks, fn chunk -> chunk.similarity >= @similarity_threshold end)

              {has_good_match, suggestion, max_similarity}

            _error ->
              {false, suggestion, 0.0}
          end
        end,
        timeout: :infinity,
        max_concurrency: 5
      )
      |> Enum.map(fn {:ok, result} -> result end)

    validated =
      results
      |> Enum.filter(fn {valid, _suggestion, _score} -> valid end)
      |> Enum.map(fn {_valid, suggestion, _score} -> suggestion end)
      |> Enum.take(5)

    validation_details =
      Enum.map(results, fn {valid, suggestion, score} ->
        %{
          "suggestion" => suggestion,
          "max_similarity" => Float.round(score, 3),
          "kept" => valid
        }
      end)

    {validated, validation_details}
  end
end
