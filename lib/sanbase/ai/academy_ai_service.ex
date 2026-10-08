defmodule Sanbase.AI.AcademyAIService do
  @moduledoc """
  Service for generating Academy Q&A responses using the aiserver API.
  Handles both registered and unregistered users.
  """

  require Logger
  alias Sanbase.Knowledge
  alias Sanbase.Knowledge.{Academy, Faq}
  alias Sanbase.OpenAI.Question
  alias Sanbase.AI.AcademyTracing, as: Tracing

  @dont_know_answer "DK"
  @dont_know_message "Sorry, I can’t seem to find anything in the Academy on that right now.\n\nTry rephrasing your question — or head over to Discord for help from other users & the Santiment team!\n\n👉 https://discord.gg/EJrZR8GHZU"
  # Picked with `AcademySearchEval.run_answers/1` on 2026-09-29: against gpt-5-nano
  # (default reasoning) the judge score went 4.71 -> 4.81 and p50 latency 9.0s -> 3.3s
  # with gpt-5.4-mini. Moved to gpt-6-luna on 2026-10-02: ~7x cheaper input and ~9x
  # cheaper output than gpt-5.4-mini, and stronger on general benchmarks.
  @model "gpt-6-luna"
  @reasoning_effort "low"
  # Follow-up suggestions run after the answer, on the user's request path.
  @suggestions_model "gpt-6-luna"
  @suggestions_reasoning_effort "none"
  @similarity_threshold 0.5

  # Earlier chat messages sent with the answer prompt.
  @history_messages 6
  # Follow-up rewriting: a small fast model, only the last turns, long answers cut.
  @rewrite_model "gpt-6-luna"
  @rewrite_history_messages 4
  @rewrite_message_chars 600
  @max_search_query_chars 300

  # Retrieve wide, rerank, keep top_k for the prompt.
  @retrieval_top_k 20
  @prompt_top_k 10

  # Hard cap on returned chunks; the GraphQL API rejects larger topK values.
  @max_top_k 50
  # Long pages (sansheets function lists, metric pages) otherwise fill every slot.
  @max_chunks_per_article 2

  # Runs synchronously in the sendChatMessage mutation; don't retry a
  # best-effort rerank on the user's request path.
  @rerank_max_retries 0

  @doc """
  Generates an Academy Q&A response for a message in the chat `chat_id`,
  using the chat's earlier messages as history. See `answer/2`.

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
    chat_history = if chat_id, do: build_chat_history(chat_id, question), else: []

    answer(question,
      chat_history: chat_history,
      user_id: user_id,
      session_id: Tracing.generate_session_id(chat_id, user_id),
      include_suggestions: include_suggestions
    )
  end

  @doc """
  Answer `question` from the Academy: search, then an LLM answer with inline
  citations, then optional follow-up suggestions.

  A follow-up question ("how do I set it up?") is first rewritten into a
  standalone search query using the history; the answer prompt gets the
  original question, the rewritten query as its interpretation, and the history.

  Options:
    * `:chat_history` - earlier messages, oldest first, as `%{role, content}`
      maps, without the current question (default `[]`)
    * `:include_suggestions` - generate follow-up suggestions (default true)
    * `:rewrite_followups` - rewrite follow-ups into standalone search queries
      (default true; false searches the raw question, for A/B evals)
    * `:model` - answer model (default `#{@model}`)
    * `:reasoning_effort` - reasoning effort of the answer model (default
      `#{inspect(@reasoning_effort)}`; nil sends none, i.e. the model's default)
    * `:search_opts` - passed to `semantic_search/2`
    * `:user_id`, `:session_id` - Langfuse tracing
    * `:tracing_environment` - Langfuse environment of the trace (default
      `Sanbase.OpenAI.Tracing.environment/0`; evals pass "eval")

  Returns `{:ok, %{answer, sources, suggestions, search_query}}`.
  """
  @spec answer(String.t(), keyword()) :: {:ok, map()} | {:error, String.t()}
  def answer(question, opts \\ []) do
    chat_history = Keyword.get(opts, :chat_history, [])
    model = Keyword.get(opts, :model, @model)

    trace =
      Tracing.start_trace(question,
        user_id: Keyword.get(opts, :user_id),
        session_id: Keyword.get(opts, :session_id),
        environment: Keyword.get(opts, :tracing_environment)
      )

    history_for_search =
      if Keyword.get(opts, :rewrite_followups, true), do: chat_history, else: []

    with {:ok, search_query} <- search_query(question, history_for_search, trace),
         {:ok, reranked_chunks} <-
           semantic_search(search_query, Keyword.get(opts, :search_opts, [])),
         {:ok, answer, sources} <-
           generate_answer(question, search_query, reranked_chunks, chat_history, trace,
             model: model,
             reasoning_effort: Keyword.get(opts, :reasoning_effort, @reasoning_effort)
           ) do
      suggestions =
        if Keyword.get(opts, :include_suggestions, true) and answer != @dont_know_message do
          case generate_suggestions(question, answer, sources, trace) do
            {:ok, suggestions} ->
              # Filter out suggestions longer than 255 characters
              Enum.filter(suggestions, fn s -> String.length(s) <= 255 end)

            _error ->
              []
          end
        else
          []
        end

      Tracing.finish_trace(trace, answer, %{
        "search_query" => search_query,
        "chunks_count" => length(reranked_chunks),
        "sources_count" => length(sources),
        "suggestions" => suggestions,
        "dont_know" => answer == @dont_know_message,
        "status" => "ok"
      })

      {:ok,
       %{answer: answer, sources: sources, suggestions: suggestions, search_query: search_query}}
    else
      {:error, reason} ->
        Logger.error("Local Academy AI request failed: #{inspect(reason)}")

        Tracing.finish_trace(trace, nil, %{"status" => "error", "error" => inspect(reason)})

        {:error, "Failed to generate Academy response"}
    end
  end

  @doc "The message returned when the Academy does not cover a question."
  @spec dont_know_message() :: String.t()
  def dont_know_message(), do: @dont_know_message

  # Without history the question is the search query. With history, a short LLM
  # call resolves references to earlier turns. On failure the raw question is
  # searched, as before.
  defp search_query(question, [], _trace), do: {:ok, question}

  defp search_query(question, chat_history, trace) do
    prompt = build_rewrite_prompt(question, chat_history)

    tracing_opts =
      trace
      |> Tracing.generation_opts("academy.qa.rewrite", @rewrite_model)
      |> Map.put(:reasoning_effort, "none")

    case Question.ask(prompt, tracing_opts) do
      {:ok, rewritten} ->
        case rewritten |> String.trim() |> String.trim("\"") do
          "" -> {:ok, question}
          query -> {:ok, String.slice(query, 0, @max_search_query_chars)}
        end

      {:error, reason} ->
        Logger.warning("Academy follow-up rewrite failed: #{inspect(reason)}")
        {:ok, question}
    end
  end

  defp build_rewrite_prompt(question, chat_history) do
    history =
      chat_history
      |> Enum.take(-@rewrite_history_messages)
      |> Enum.map_join("\n", fn msg ->
        "#{String.capitalize(msg.role)}: #{String.slice(msg.content, 0, @rewrite_message_chars)}"
      end)

    """
    Rewrite the user's latest question as one standalone search query for the Santiment \
    Academy documentation. Use the conversation only to fill in what the latest question \
    leaves implicit, such as what "it", "that metric" or "the plan" refers to. Keep the \
    user's own terms. If the latest question is already standalone, return it unchanged. \
    Reply with the query only, no quotes or explanation.

    Conversation:
    #{history}

    Latest question: #{question}
    """
  end

  @doc """
  Run the Academy semantic search pipeline (vector retrieval + rerank) WITHOUT
  the LLM synthesis step.

  This is the retrieval half of `generate_local_response/4`, exposed on its own
  so callers that want to run their own LLM (e.g. the AI server) can reuse
  Santiment's Academy index and reranking instead of reproducing the pipeline.

  Returns the reranked chunks ordered by relevance. Each chunk is a map with
  keys such as `:title`, `:url`, `:heading`, `:chunk` (the chunk text) and
  `:similarity`.

  ## Options

    * `:top_k` - number of chunks to return after reranking (default: #{@prompt_top_k})
    * `:retrieval_top_k` - number of candidate chunks pulled from the vector
      store before reranking. Coerced up to at least `:top_k` (default: #{@retrieval_top_k})
    * `:max_chunks_per_article` - at most this many chunks per article are
      returned while other articles can fill the slots; `nil` disables the cap
      (default: #{@max_chunks_per_article})
    * `:reranker` - reranker module override (used by the eval)

  `:top_k` is clamped to 1..#{@max_top_k}.
  """
  @spec semantic_search(String.t(), keyword()) :: {:ok, list(map())} | {:error, term()}
  def semantic_search(question, opts \\ []) when is_binary(question) do
    top_k = opts |> Keyword.get(:top_k, @prompt_top_k) |> clamp(1, @max_top_k)
    retrieval_top_k = max(Keyword.get(opts, :retrieval_top_k, @retrieval_top_k), top_k)
    per_article = Keyword.get(opts, :max_chunks_per_article, @max_chunks_per_article)

    rerank_opts =
      [top_n: retrieval_top_k, max_retries: @rerank_max_retries]
      |> Keyword.merge(Keyword.take(opts, [:reranker]))

    with {:ok, chunks} <- Academy.search_chunks(question, retrieval_top_k) do
      reranked_chunks =
        question
        |> Knowledge.rerank_entries(chunks, :academy, rerank_opts)
        |> cap_per_article(per_article)
        |> Enum.take(top_k)

      {:ok, reranked_chunks}
    end
  end

  # Keep reranked order but let at most `limit` chunks of one article through
  # before other articles; the overflow is appended so small result sets are
  # still filled.
  defp cap_per_article(chunks, nil), do: chunks

  defp cap_per_article(chunks, limit) when is_integer(limit) and limit > 0 do
    {kept, overflow, _counts} =
      Enum.reduce(chunks, {[], [], %{}}, fn chunk, {kept, overflow, counts} ->
        count = Map.get(counts, chunk.article_id, 0)

        if count < limit do
          {[chunk | kept], overflow, Map.put(counts, chunk.article_id, count + 1)}
        else
          {kept, [chunk | overflow], counts}
        end
      end)

    Enum.reverse(kept) ++ Enum.reverse(overflow)
  end

  defp clamp(value, min, max) when is_integer(value), do: value |> max(min) |> min(max)
  defp clamp(_value, min, _max), do: min

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
  Question suggestions for the Academy search box, matched locally against
  the stored per-article questions (see `Sanbase.Knowledge.AcademyQuestions`).
  """
  @spec autocomplete_questions(String.t()) :: {:ok, [map()]}
  def autocomplete_questions(query) do
    {:ok, Sanbase.Knowledge.AcademyQuestions.suggest(query)}
  end

  # The latest messages of the chat, oldest first, without the current question
  # (the resolver stores it before generating the answer).
  defp build_chat_history(chat_id, question) do
    chat_id
    |> Sanbase.Chat.get_latest_chat_messages(@history_messages + 1)
    |> Enum.map(&%{role: Atom.to_string(&1.role), content: &1.content})
    |> drop_current_question(question)
    |> Enum.take(-@history_messages)
  end

  defp drop_current_question(messages, question) do
    case List.last(messages) do
      %{role: "user", content: ^question} -> Enum.drop(messages, -1)
      _ -> messages
    end
  end

  defp generate_answer(question, search_query, chunks, chat_history, trace, model_opts) do
    prompt = build_answer_prompt(question, search_query, chunks, chat_history)
    model = Keyword.fetch!(model_opts, :model)

    tracing_opts =
      trace
      |> Tracing.generation_opts("academy.qa.answer", model, %{"chunks_count" => length(chunks)})
      |> maybe_put_reasoning_effort(model_opts[:reasoning_effort])

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

  defp maybe_put_reasoning_effort(tracing_opts, nil), do: tracing_opts

  defp maybe_put_reasoning_effort(tracing_opts, effort),
    do: Map.put(tracing_opts, :reasoning_effort, effort)

  defp build_answer_prompt(question, search_query, chunks, chat_history) do
    context = build_context_from_chunks(chunks)
    history_context = build_history_context(chat_history)
    system_prompt = build_academy_system_prompt(context, history_context)

    "#{system_prompt}\n\nQuestion: #{question}#{interpretation(question, search_query)}"
  end

  # A terse follow-up ("which metrics") alone makes the answer model reply "DK"
  # even with relevant sources, so spell out what the rewrite resolved it to.
  defp interpretation(question, search_query) when search_query == question, do: ""
  defp interpretation(_question, search_query), do: "\n(Interpreted as: #{search_query})"

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
      |> Enum.take(-@history_messages)
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

  defp generate_suggestions(question, answer, sources, trace) do
    tracing_opts =
      trace
      |> Tracing.generation_opts("academy.qa.suggestions.generate", @suggestions_model)
      |> Map.put(:reasoning_effort, @suggestions_reasoning_effort)

    with {:ok, raw_suggestions} <-
           call_suggestions_llm(question, answer, sources, tracing_opts),
         {validated, validation_details} <- validate_suggestions(raw_suggestions) do
      Tracing.log_validation_event(
        trace,
        raw_suggestions,
        validated,
        validation_details,
        @similarity_threshold
      )

      {:ok, validated}
    end
  end

  defp call_suggestions_llm(question, answer, sources, tracing_opts) do
    {:ok, broader_chunks} = Academy.search_chunks(question, 5)

    prompt = build_suggestions_prompt(question, answer, sources, broader_chunks)

    case Question.ask(prompt, tracing_opts) do
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
    - Keep each question under 100 characters for brevity and clarity

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
