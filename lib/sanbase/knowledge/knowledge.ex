defmodule Sanbase.Knowledge do
  require Logger

  alias Sanbase.Knowledge.Context
  alias Sanbase.Knowledge.Reranker
  alias Sanbase.Knowledge.Reranker.CandidateFormatter

  @default_min_similarity 0.35
  @no_answer_message "I don't have enough information in the available Santiment FAQ, Academy, or Insights content to answer this question. Please contact Santiment Support for further assistance."

  # Coarse retrieval fans out beyond what the prompt can hold so the
  # reranker has headroom to reorder. The reranker truncates back to
  # @prompt_top_n before prompt assembly.
  @retrieval_top_k 20
  @prompt_top_n 5

  @doc """
  Number of reranked hits per source that reach the answer prompt. Exposed so
  the eval harness measures context over the same window the live prompt uses.
  """
  def prompt_top_n(), do: @prompt_top_n

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
      |> Keyword.take([:faq, :academy, :insight])
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
          insight: length(filtered_insights)
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
          "smart_search done: question=#{preview} outcome=ok took_ms=#{took_ms} reranker=#{reranker} faqs=#{counts.faqs} academy=#{counts.academy} insight=#{counts.insight} no_answer=#{no_answer?}"
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
  Rerank `entries` for `source` against `query`, returning the original maps
  reordered by relevance (truncated to `:top_n` if given). Falls back to input
  order on backend error. Options other than `:reranker`/`:top_n` are forwarded
  to the backend.
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
    #{if options[:insight], do: insights_text}
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
          entries_text = Context.assemble(faq_entries, :faq)

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
    if Keyword.get(options, :insight, true) do
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
    if Keyword.get(options, :insight, true) do
      with {:ok, raw_chunks} <- find_most_similar_insight_chunks(embedding, @retrieval_top_k) do
        post_embeddings =
          raw_chunks
          |> filter_by_similarity(min_sim)
          |> rerank(user_input, :insight, options, top_n: @prompt_top_n)

        if post_embeddings == [] do
          {:ok, prompt, false}
        else
          text_chunks = Context.assemble(post_embeddings, :insight)

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
            academy_text_chunks = Context.assemble(academy_chunks, :academy)

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
    <Grounding>
    - Use the provided content (FAQ, Academy, Insights, etc.) as the SOLE basis for your answer.
      Do not add information, assumptions, or outside knowledge that is not present in it.
    - If the content does not contain enough information to answer, clearly state that you cannot
      answer based on the available data. Answer the parts you can and explicitly flag the parts you cannot.
    - If the content is similar but not an exact match, say so, clarify the context, and suggest
      contacting Santiment Support if needed.
    - If the question is unclear or ambiguous, ask for clarification using only the information provided.
    - Prioritize accuracy and transparency: when uncertain, state the limitation rather than guessing.
    </Grounding>

    <Answer_Style>
    - Respond as a professional support agent: direct, with no greetings, introductions, or congratulations.
    - Open with a one- or two-sentence direct answer to the main question, then expand. Do not make the
      user read to the end for the takeaway.
    - Match length to the question: a short factual question gets a short answer; a broad "how to..."
      gets fuller treatment. Prefer the shortest answer that is still complete.
    - Expand acronyms and name metrics in full on first use — e.g. "MVRV (Market Value to Realized
      Value)" — so a non-expert can follow.
    - Format in markdown for easy scanning. Use `###` for main sections and `####` for sub-sections
      (the answer is displayed under an "Answer" heading, so do NOT use `#` or `##`). Use bullet points,
      bold, italics, and code blocks where they aid clarity.
    - When a part of the question is procedural ("how to..."), give the answer as concrete numbered steps
      rather than prose.
    - When comparing variants, thresholds, or options, use a markdown table if it scans better than bullets.
    - If the question contains multiple parts or distinct sub-questions, structure the answer into clearly
      labeled sections — one per part, each under its own heading mirroring that part — so every part is
      addressed explicitly and the answer is visually split.
    - Where useful, end with a brief summary or the key actionable steps.
    - All of the above is guidance, not rigid rules: when a convention (sectioning, tables, steps) would
      add noise rather than clarity — for example a single focused question — ignore it and just answer directly.
    </Answer_Style>

    <Citations_And_Links>
    - Every provided context block has a `Source marker:` line of the form `[Source] [label](url)`, where
      `[Source]` is a `[FAQ]`, `[Insight]`, or `[Academy]` tag showing where it came from, followed by a markdown link.
    - Cite claims by reproducing that marker VERBATIM — keep the leading tag (write just `[FAQ]`, not
      `[Source][FAQ]`), the link label, and the URL exactly. Place the marker inline immediately after the
      sentence or claim it supports.
    - When several consecutive sentences rely on the same source, cite it once at the end of that claim or
      paragraph instead of after every sentence. Every distinct claim must stay attributable, but do not
      repeat an identical marker line after line.
    - Only use links explicitly included in the provided content. Do not invent or hallucinate markers,
      links, labels, or URLs, and do not convert links to plain text.
    - End the answer with a `Sources` section listing each unique cited marker on its own bullet,
      reproducing the same `[<Source>] [label](url)` marker verbatim (one per unique source).
    </Citations_And_Links>
    </Instructions>

    <User_Input>
    #{question}
    </User_Input>
    """

    {:ok, prompt}
  end
end
