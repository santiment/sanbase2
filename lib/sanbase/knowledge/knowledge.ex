defmodule Sanbase.Knowledge do
  require Logger

  alias Sanbase.Knowledge.Reranker
  alias Sanbase.Knowledge.Reranker.CandidateFormatter

  @default_min_similarity 0.35
  @no_answer_message "I don't have enough information in the available Santiment FAQ, Academy, or Insights content to answer this question. Please contact Santiment Support for further assistance."

  # Coarse retrieval fans out beyond what the prompt can hold so the
  # reranker has headroom to reorder. The reranker truncates back to
  # @prompt_top_n before prompt assembly.
  @retrieval_top_k 20
  @prompt_top_n 5

  def answer_question(user_input, options \\ []) do
    reranker = Reranker.label(Keyword.get(options, :reranker) || Reranker.default_impl())
    preview = question_preview(user_input)

    Logger.info(
      "answer_question start: question=#{preview} question_len=#{byte_size(user_input)} reranker=#{reranker}"
    )

    start_mono = System.monotonic_time()

    result =
      with {:ok, [embedding]} <- Sanbase.AI.Embedding.generate_embeddings([user_input], 1536),
           {:ok, prompt, sources_found?} <-
             build_question_answer_prompt(user_input, embedding, options) do
        if sources_found? do
          Sanbase.OpenAI.Question.ask(prompt)
        else
          {:ok, @no_answer_message}
        end
      end

    took_ms =
      System.convert_time_unit(System.monotonic_time() - start_mono, :native, :millisecond)

    case result do
      {:ok, _} ->
        Logger.info(
          "answer_question done: question=#{preview} outcome=ok took_ms=#{took_ms} reranker=#{reranker}"
        )

      {:error, reason} ->
        Logger.info(
          "answer_question done: question=#{preview} outcome=error took_ms=#{took_ms} reranker=#{reranker} reason=#{inspect(reason)}"
        )
    end

    result
  end

  def smart_search(user_input, options) do
    min_sim = min_similarity(options)
    reranker = Reranker.label(Keyword.get(options, :reranker) || Reranker.default_impl())
    preview = question_preview(user_input)

    sources =
      options
      |> Keyword.take([:faq, :academy, :insights])
      |> Enum.filter(fn {_k, v} -> v end)
      |> Enum.map(fn {k, _} -> k end)

    Logger.info(
      "smart_search start: question=#{preview} question_len=#{byte_size(user_input)} reranker=#{reranker} sources=#{inspect(sources)}"
    )

    start_mono = System.monotonic_time()

    result =
      with {:ok, [embedding]} <-
             Sanbase.AI.Embedding.generate_embeddings([user_input], 1536),
           {:ok, faq_entries} <-
             maybe_find_most_similar_faqs(user_input, embedding, options, min_sim),
           {:ok, academy_articles} <-
             maybe_find_most_similar_academy_articles(user_input, embedding, options, min_sim),
           {:ok, insights} <-
             maybe_find_most_similar_insights(user_input, embedding, options, min_sim) do
        filtered_faqs = filter_by_similarity(faq_entries, min_sim)
        filtered_academy = filter_by_similarity(academy_articles, min_sim)
        filtered_insights = filter_by_similarity(insights, min_sim)

        counts = %{
          faqs: length(filtered_faqs),
          academy: length(filtered_academy),
          insights: length(filtered_insights)
        }

        if filtered_faqs == [] and filtered_academy == [] and filtered_insights == [] do
          {{:ok, @no_answer_message}, counts, true}
        else
          {build_smart_search_result(filtered_faqs, filtered_academy, filtered_insights, options),
           counts, false}
        end
      end

    took_ms =
      System.convert_time_unit(System.monotonic_time() - start_mono, :native, :millisecond)

    case result do
      {{:ok, _} = ret, counts, no_answer?} ->
        Logger.info(
          "smart_search done: question=#{preview} outcome=ok took_ms=#{took_ms} reranker=#{reranker} faqs=#{counts.faqs} academy=#{counts.academy} insights=#{counts.insights} no_answer=#{no_answer?}"
        )

        ret

      {:error, reason} = ret ->
        Logger.info(
          "smart_search done: question=#{preview} outcome=error took_ms=#{took_ms} reranker=#{reranker} reason=#{inspect(reason)}"
        )

        ret
    end
  end

  @doc """
  Rerank coarse-retrieval `entries` for `source` against `query` and return
  the original entry maps re-ordered by relevance (optionally truncated to
  `:top_n`).

  `entries` are the raw retrieval maps for the source (FAQ rows, Academy
  chunks, Insight chunks). They are normalized to reranker candidates via
  `CandidateFormatter`, reranked by the configured backend, and unwrapped
  back to the same maps — so callers get their input shape back, only
  reordered and (optionally) shortened.

  Options:

    * `:reranker` — reranker module override; defaults to
      `Reranker.default_impl/0`.
    * `:top_n` — truncate the reranked list to this many entries.

  Any other option is forwarded to the backend. On a backend error the
  dispatcher falls back to input order (truncated to `:top_n`), so this
  never raises or fails the caller — it can only improve ordering.
  """
  @spec rerank_entries(String.t(), [map()], CandidateFormatter.source(), keyword()) :: [map()]
  def rerank_entries(query, entries, source, opts \\ [])

  def rerank_entries(_query, [], _source, _opts), do: []

  def rerank_entries(query, entries, source, opts) do
    reranker_mod = Keyword.get(opts, :reranker) || Reranker.default_impl()

    rerank_opts =
      opts
      |> Keyword.put(:source, source)
      |> Keyword.put_new(:reranker, reranker_mod)

    entries
    |> CandidateFormatter.to_candidates(source, reranker_mod)
    |> then(&Reranker.call(query, &1, rerank_opts))
    |> Enum.map(& &1.metadata)
  end

  # Private functions

  defp build_smart_search_result(faq_entries, academy_articles, insights, options) do
    format_similarity = fn similarity ->
      if is_float(similarity),
        do: :erlang.float_to_binary(similarity, decimals: 2),
        else: "embedding missing"
    end

    faqs_text =
      Enum.map(faq_entries, fn entry ->
        "- [#{format_similarity.(entry.similarity)}] [#{entry.question}](#{SanbaseWeb.Endpoint.admin_url()}/admin/faq/#{entry.id})"
      end)
      |> Enum.join("\n")

    faqs_text = "FAQs:\n" <> faqs_text <> "\n"

    insights_text =
      Enum.map(insights, fn insight ->
        "- [#{format_similarity.(insight.similarity)}] [#{insight.post_title}](#{SanbaseWeb.Endpoint.insight_url(insight.post_id)})"
      end)
      |> Enum.join("\n")

    insights_text = "Insights:\n" <> insights_text <> "\n"

    academy_text =
      Enum.map(academy_articles, fn article ->
        "- [#{format_similarity.(article.similarity)}] [#{article.title}](#{article.url})"
      end)
      |> Enum.join("\n")

    academy_text = "Academy:\n" <> academy_text <> "\n"

    answer = """
    #{if options[:faq], do: faqs_text}
    #{if options[:insights], do: insights_text}
    #{if options[:academy], do: academy_text}
    """

    {:ok, answer}
  end

  defp build_question_answer_prompt(user_input, embedding, options) do
    min_sim = min_similarity(options)

    with {:ok, prompt} <- generate_initial_prompt(user_input),
         {:ok, prompt, faq_found?} <-
           maybe_add_similar_faqs(prompt, user_input, embedding, options, min_sim),
         {:ok, prompt, insights_found?} <-
           maybe_add_similar_insight_chunks(prompt, user_input, embedding, options, min_sim),
         {:ok, prompt, academy_found?} <-
           maybe_add_similar_academy_chunks(prompt, user_input, embedding, options, min_sim) do
      {:ok, prompt, faq_found? or insights_found? or academy_found?}
    end
  end

  defp maybe_add_similar_faqs(prompt, user_input, embedding, options, min_sim) do
    if Keyword.get(options, :faq, true) do
      with {:ok, raw_entries} <- find_most_similar_faqs(embedding, @retrieval_top_k) do
        faq_entries =
          raw_entries
          |> filter_by_similarity(min_sim)
          |> rerank(user_input, :faq, options, top_n: @prompt_top_n)

        if faq_entries == [] do
          {:ok, prompt, false}
        else
          entries_text =
            Enum.map(faq_entries, fn faq_entry ->
              url = "#{SanbaseWeb.Endpoint.admin_url()}/admin/faq/#{faq_entry.id}"

              """
              Source marker: [FAQ ##{faq_entry.id}](#{url})
              Question: #{faq_entry.question}
              Answer: #{faq_entry.answer_markdown}
              """
            end)
            |> Enum.join("\n")

          prompt =
            prompt <>
              """
              <Similar_FAQ_Entries>
              #{entries_text}
              </Similar_FAQ_Entries>
              """

          {:ok, prompt, true}
        end
      end
    else
      {:ok, prompt, false}
    end
  end

  defp maybe_find_most_similar_faqs(user_input, embedding, options, min_sim) do
    if Keyword.get(options, :faq, true) do
      with {:ok, raw} <- find_most_similar_faqs(embedding, @retrieval_top_k) do
        {:ok,
         raw
         |> filter_by_similarity(min_sim)
         |> rerank(user_input, :faq, options, top_n: @prompt_top_n)}
      end
    else
      {:ok, []}
    end
  end

  defp min_similarity(options) do
    Keyword.get(options, :min_similarity, @default_min_similarity)
  end

  @question_preview_chars 40

  defp question_preview(user_input) when is_binary(user_input) do
    flat = user_input |> String.replace(~r/\s+/, " ") |> String.trim()

    truncated =
      if String.length(flat) > @question_preview_chars do
        String.slice(flat, 0, @question_preview_chars) <> "…"
      else
        flat
      end

    inspect(truncated)
  end

  defp filter_by_similarity(entries, min_sim) do
    Enum.filter(entries, fn entry ->
      case Map.get(entry, :similarity) do
        nil -> false
        sim when is_number(sim) -> sim >= min_sim
        _ -> false
      end
    end)
  end

  defp find_most_similar_faqs(embedding, size) do
    Sanbase.Knowledge.Faq.find_most_similar_faqs(embedding, size)
  end

  defp find_most_similar_insight_chunks(embedding, size) do
    Sanbase.Insight.Post.find_most_similar_insight_chunks(embedding, size)
  end

  defp maybe_find_most_similar_insights(user_input, embedding, options, min_sim) do
    if Keyword.get(options, :insights, true) do
      with {:ok, raw} <- find_most_similar_insights(embedding, @retrieval_top_k) do
        {:ok,
         raw
         |> filter_by_similarity(min_sim)
         |> rerank(user_input, :insight, options, top_n: @prompt_top_n)}
      end
    else
      {:ok, []}
    end
  end

  defp find_most_similar_insights(embedding, size) do
    Sanbase.Insight.Post.find_most_similar_insights(embedding, size)
  end

  defp maybe_add_similar_insight_chunks(prompt, user_input, embedding, options, min_sim) do
    if Keyword.get(options, :insights, true) do
      with {:ok, raw_chunks} <- find_most_similar_insight_chunks(embedding, @retrieval_top_k) do
        post_embeddings =
          raw_chunks
          |> filter_by_similarity(min_sim)
          |> rerank(user_input, :insight, options, top_n: @prompt_top_n)

        if post_embeddings == [] do
          {:ok, prompt, false}
        else
          text_chunks =
            Enum.map(post_embeddings, fn chunk ->
              url = SanbaseWeb.Endpoint.insight_url(chunk.post_id)

              """
              Source marker: [#{chunk.post_title}](#{url})
              #{chunk.text_chunk}
              """
            end)
            |> Enum.join("\n\n")

          prompt =
            prompt <>
              """
              <Most_Similar_Santiment_Insight_Chunks>
              #{text_chunks}
              </Most_Similar_Santiment_Insight_Chunks>
              """

          {:ok, prompt, true}
        end
      end
    else
      {:ok, prompt, false}
    end
  end

  defp maybe_find_most_similar_academy_articles(user_input, embedding, options, min_sim) do
    if Keyword.get(options, :academy, true) do
      with {:ok, raw} <- Sanbase.Knowledge.Academy.search_articles(embedding, @retrieval_top_k) do
        {:ok,
         raw
         |> filter_by_similarity(min_sim)
         |> rerank(user_input, :academy, options, top_n: @prompt_top_n)}
      end
    else
      {:ok, []}
    end
  end

  defp maybe_add_similar_academy_chunks(prompt, user_input, embedding, options, min_sim) do
    if Keyword.get(options, :academy, true) do
      case Sanbase.Knowledge.Academy.search_chunks(embedding, @retrieval_top_k) do
        {:ok, raw_chunks} ->
          academy_chunks =
            raw_chunks
            |> filter_by_similarity(min_sim)
            |> rerank(user_input, :academy, options, top_n: @prompt_top_n)

          if academy_chunks == [] do
            {:ok, prompt, false}
          else
            academy_text_chunks =
              Enum.map(academy_chunks, fn academy_chunk ->
                """
                Source marker: [#{academy_chunk.title}](#{academy_chunk.url})
                Most relevant chunk from article: #{academy_chunk.chunk}
                """
              end)
              |> Enum.join("\n")

            prompt =
              prompt <>
                """
                <Academy_Content>
                #{academy_text_chunks}
                </Academy_Content>
                """

            {:ok, prompt, true}
          end

        _ ->
          {:ok, prompt, false}
      end
    else
      {:ok, prompt, false}
    end
  end

  defp rerank(entries, user_input, source, options, opts) do
    rerank_entries(user_input, entries, source, maybe_put_reranker(opts, options))
  end

  defp maybe_put_reranker(opts, options) do
    case Keyword.get(options, :reranker) do
      nil -> opts
      mod -> Keyword.put(opts, :reranker, mod)
    end
  end

  defp generate_initial_prompt(question) do
    prompt = """
    <Role>
    You are a knowledgeable and helpful Support Specialist at Santiment, with deep expertise in crypto,
    programming, trading, and both technical and non-technical support.
    You excel at clear, concise communication and can explain complex topics in simple, user-friendly language.
    Your primary objective is to provide the most accurate and helpful answer to the User Input, using only the information provided.
    </Role>

    <Instructions>
    1. Carefully review the provided content (FAQ, Academy, Insights, etc.) and use it as the sole basis for your answer to the user's question.
    2. Respond as a professional support agent: be concise, direct, and avoid any greetings, introductions, or congratulations.
    3. If the provided content does not contain enough information to answer the question, clearly state that you cannot answer based on the available data.
    4. Format your response in markdown. Use headings, bullet points, bold, italics, and code blocks where appropriate for clarity.
    5. When referencing links, only use those explicitly included in the provided content. Do not invent or hallucinate links.
    6. If you find information that is similar but not an exact match, explain this to the user, clarify the context,
       and suggest contacting Santiment Support for further assistance if needed.
    7. Do not include any information, assumptions, or external knowledge that is not present in the provided content.
    8. If the user's question is unclear or ambiguous, politely ask for clarification using only the information provided.
    9. Prioritize accuracy and transparency—if there is any uncertainty, clearly communicate the limitations of the available information.
    10. When possible, summarize key points or actionable steps to help the user resolve their issue efficiently.
    11. Every provided context block has a `Source marker:` line containing a markdown link `[label](url)`.
        Cite every claim by reproducing that markdown link VERBATIM (brackets, label, parentheses, and URL — all preserved).
        Place the marker inline immediately after the sentence or bullet it supports.
        Do not invent markers, do not omit them, do not rewrite the label or URL, and do not convert links to plain text.
    12. End the answer with a `Sources` section listing each unique cited marker on its own bullet,
        reproducing the same `[label](url)` markdown link verbatim (one per unique source).
    </Instructions>

    <User_Input>
    #{question}
    </User_Input>
    """

    {:ok, prompt}
  end
end
