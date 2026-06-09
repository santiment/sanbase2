defmodule Sanbase.Knowledge do
  require Logger

  alias Sanbase.Knowledge.AnswerModel
  alias Sanbase.Knowledge.Citations
  alias Sanbase.Knowledge.Context
  alias Sanbase.Knowledge.ContextExpansion
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
           {:ok, prompt, registry} <-
             build_question_answer_prompt(user_input, embedding, options) do
        if registry == [] do
          {:ok, @no_answer_message}
        else
          ask_answer(prompt, registry, options)
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
    # NOTE: `:context_expansion` is intentionally not applied here. Neighbour
    # expansion only enriches the answer prompt (see `answer_question/2`); smart
    # search returns links, so the option is a no-op on this path.
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

  # Build the answer prompt and the citation registry together. Each enabled
  # source contributes its final reranked hits; the hits are numbered globally
  # (FAQ, then Insight, then Academy) so every context block carries a stable
  # `[<id>]` the model cites by, and the returned `registry` maps each id to the
  # `{source, prefix, label, url}` marker `Citations` turns into real links.
  # An empty registry means no source cleared the similarity threshold.
  defp build_question_answer_prompt(user_input, embedding, options) do
    min_sim = min_similarity(options)

    with {:ok, base_prompt} <- generate_initial_prompt(user_input),
         {:ok, faq_hits} <- answer_faq_hits(user_input, embedding, options, min_sim),
         {:ok, insight_hits} <- answer_insight_hits(user_input, embedding, options, min_sim),
         {:ok, academy_hits} <- answer_academy_hits(user_input, embedding, options, min_sim) do
      {numbered, registry} =
        number_sources([{:faq, faq_hits}, {:insight, insight_hits}, {:academy, academy_hits}])

      prompt =
        base_prompt
        |> append_section(:faq, numbered[:faq])
        |> append_section(:insight, numbered[:insight])
        |> append_section(:academy, numbered[:academy])

      {:ok, prompt, registry}
    end
  end

  # Assign each hit a globally-unique `:marker_id` in source order, and build the
  # parallel registry of markers (with that id) the answer post-processing needs.
  defp number_sources(source_hits) do
    {numbered, registry, _next} =
      Enum.reduce(source_hits, {%{}, [], 1}, fn {source, hits}, {numbered, registry, next} ->
        {tagged, registry, next} =
          Enum.reduce(hits, {[], registry, next}, fn hit, {tagged, registry, id} ->
            marker = hit |> Context.marker(source) |> Map.put(:id, id)
            {[Map.put(hit, :marker_id, id) | tagged], [marker | registry], id + 1}
          end)

        {Map.put(numbered, source, Enum.reverse(tagged)), registry, next}
      end)

    {numbered, Enum.reverse(registry)}
  end

  @section_tags %{
    faq: "Similar_FAQ_Entries",
    insight: "Most_Similar_Santiment_Insight_Chunks",
    academy: "Academy_Content"
  }

  defp append_section(prompt, _source, []), do: prompt

  defp append_section(prompt, source, hits) do
    tag = Map.fetch!(@section_tags, source)

    prompt <>
      """
      <#{tag}>
      #{Context.assemble(hits, source)}
      </#{tag}>
      """
  end

  defp answer_faq_hits(user_input, embedding, options, min_sim) do
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

  defp answer_insight_hits(user_input, embedding, options, min_sim) do
    if Keyword.get(options, :insight, true) do
      with {:ok, raw_chunks} <- find_most_similar_insight_chunks(embedding, @retrieval_top_k) do
        {:ok,
         raw_chunks
         |> filter_by_similarity(min_sim)
         |> rerank(user_input, :insight, options)
         |> diversify_by_document(& &1.post_id, @prompt_top_n)
         |> maybe_expand_context(:insight, options)}
      end
    else
      {:ok, []}
    end
  end

  defp answer_academy_hits(user_input, embedding, options, min_sim) do
    if Keyword.get(options, :academy, true) do
      with {:ok, raw_chunks} <-
             Sanbase.Knowledge.Academy.search_chunks(embedding, @retrieval_top_k) do
        {:ok,
         raw_chunks
         |> filter_by_similarity(min_sim)
         |> rerank(user_input, :academy, options)
         |> diversify_by_document(& &1.article_id, @prompt_top_n)
         |> maybe_expand_context(:academy, options)}
      end
    else
      {:ok, []}
    end
  end

  # Send the assembled prompt to the configured answer client, asking for the
  # structured JSON answer, then render it (inline links + grouped Sources). The
  # client is pluggable so the answer step alone can be pointed at a different
  # model (e.g. DeepSeek via OpenRouter) without touching embeddings or rerank.
  defp ask_answer(prompt, registry, options) do
    ask_opts =
      %{response_format: Citations.response_format()}
      |> maybe_put(:model, Keyword.get(options, :answer_model))

    case AnswerModel.client(options).ask(prompt, ask_opts) do
      {:ok, content} -> {:ok, Citations.render(content, registry)}
      other -> other
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

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

  defp rerank(entries, user_input, source, options, opts \\ []) do
    rerank_entries(user_input, entries, source, maybe_put_reranker(opts, options))
  end

  @doc """
  Diversity rerank by source document. `hits` arrive in reranked order;
  multiple hits can belong to the same document (insight `post_id`, academy
  `article_id`), and without intervention the top slots can fill with several
  chunks of ONE document — collapsing to a single citation. This selects in
  round-robin order: the best remaining chunk of each distinct document first
  (maximising how many documents, and thus citations, reach the prompt), then
  second chunks, and so on, until `limit` chunks are chosen. When few documents
  matched, later rounds backfill from those documents so the prompt is never
  under-filled. Reranked order is preserved within and across groups, so this
  is a degenerate Maximal Marginal Relevance whose diversity signal is the
  exact source key (`key_fn.(hit)`) rather than an embedding-similarity estimate.
  """
  @spec diversify_by_document([map()], (map() -> term()), non_neg_integer()) :: [map()]
  def diversify_by_document(hits, key_fn, limit) do
    hits
    |> ordered_groups_by(key_fn)
    |> round_robin()
    |> Enum.take(limit)
  end

  # Group `hits` by `key_fn` into a list of chunk-lists, preserving (a) the
  # reranked order of chunks within each group and (b) the order in which each
  # group's first (best) chunk appeared.
  defp ordered_groups_by(hits, key_fn) do
    grouped = Enum.group_by(hits, key_fn)

    hits
    |> Enum.map(key_fn)
    |> Enum.uniq()
    |> Enum.map(&Map.fetch!(grouped, &1))
  end

  # Flatten a list of groups by taking one chunk from each in turn: every head
  # in group order, then recurse on the tails. Empty groups drop out.
  defp round_robin(groups) do
    case Enum.reject(groups, &(&1 == [])) do
      [] -> []
      non_empty -> Enum.map(non_empty, &hd/1) ++ round_robin(Enum.map(non_empty, &tl/1))
    end
  end

  # Optionally widen each reranked chunk with its document neighbours before the
  # text is assembled into the prompt. Off unless `:context_expansion` is true,
  # so the default behaviour is unchanged.
  defp maybe_expand_context(hits, source, options) do
    if Keyword.get(options, :context_expansion, false) do
      ContextExpansion.expand(hits, source)
    else
      hits
    end
  end

  defp maybe_put_reranker(opts, options) do
    case Keyword.get(options, :reranker) do
      nil -> opts
      mod -> Keyword.put(opts, :reranker, mod)
    end
  end

  defp generate_initial_prompt(question) do
    today = Date.to_iso8601(Date.utc_today())

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

    <Not_Financial_Advice>
    - You provide GENERAL, EDUCATIONAL information about Santiment's data, metrics, and tools. You are NOT a
      licensed financial adviser and MUST NOT give personalized investment advice. (Under the US Investment
      Advisers Act and EU MiFID II / MiCA, it is PERSONALIZED recommendations that are regulated; general,
      impersonal education is not — so staying general is the protection, not a disclaimer alone.)
    - Describe, do not direct. Explain how a metric or indicator works, what it measures, and how traders
      GENERALLY interpret it or how it has HISTORICALLY behaved, in neutral terms. Write "MVRV (Market Value
      to Realized Value) has historically tended to be elevated near market tops" — NOT "sell when MVRV is high".
    - NEVER:
      - Tell the user what to buy, sell, or hold, or name a specific asset they should trade.
      - Tell the user WHEN to enter or exit, or say that now is a good time to buy or sell.
      - Give price targets, forecasts, or predictions, or guarantee or imply any outcome.
      - Tailor the answer to the user's personal situation (portfolio, capital, risk tolerance, goals), or
        present a metric reading as a signal that they personally should act on.
      - State or imply that acting on the information is suitable or recommended for the user.
    - If the user asks for a recommendation or a personalized decision (e.g. "should I buy X now?", "is this a
      good time to sell?"), do NOT answer it directly. Explain the relevant metrics and general methodology,
      state that you cannot provide personalized investment advice, and suggest they do their own research and
      consult a licensed financial professional.
    - When (and only when) the answer touches trading, investing, buying, selling, or market timing, set the
      `financial_disclaimer` output field to `true` so the standard disclaimer is appended for you. Set it to
      `false` for purely technical, account, or product questions. Do NOT write the disclaimer text yourself.
    </Not_Financial_Advice>

    <Content_Freshness>
    - Today's date is #{today}. Use it to judge whether dated content is still current.
    - Each Insight context block shows `Published: <date> (<N> days ago)`. Treat that insight as a snapshot of
      conditions AS OF that date; the older it is, the more likely anything time-sensitive in it is outdated.
    - NEVER repeat time-bound specifics from an insight as if they are current — in particular exact prices,
      price levels, entry / stop-loss / take-profit numbers, "current" sentiment / funding / whale / on-chain
      readings, recent events, or short-term predictions. Those described the market on the publication date,
      NOT today. (Example of what to avoid: quoting an old post's "enter near 36,600, target 40,000" when that
      price is long out of date.)
    - Extract the DURABLE takeaway — the method, e.g. how a metric or signal is used to read tops and bottoms —
      rather than the dated specifics. Methodology does not expire; specific numbers, levels, and calls do.
    - Use the `(<N> days ago)` age to decide how to handle any SPECIFIC data value an insight reports — a price,
      an MVRV reading, a funding rate, a social-volume count, a level, etc.:
      - If the insight is RECENT (published within roughly the last day), you MAY state the specific value, but
        always anchored to its date — e.g. "MVRV was 2.0 on May 5, 2026" — so the reader sees it is a
        point-in-time reading, not a live value.
      - If the insight is OLDER than that, do NOT state its specific data values, prices, or levels at all —
        they are stale and would mislead. Use only the durable methodology (how the metric or signal is used),
        described in general terms.
    - FAQ and Academy content is maintained as reference material, so this caution applies most strongly to
      Insights; still apply the same judgment to any clearly time-bound statement from any source.
    </Content_Freshness>

    <Answer_Style>
    - Respond as a professional support agent: direct, with no greetings, introductions, or congratulations.
    - Open with a one- or two-sentence direct answer to the main question, then expand. Do not make the
      user read to the end for the takeaway.
    - Match length to the question: a short factual question gets a short answer; a broad "how to..."
      gets fuller treatment. Prefer the shortest answer that is still complete.
    - Expand acronyms and name metrics in full on first use — e.g. "MVRV (Market Value to Realized
      Value)" — so a non-expert can follow.
    - Format the `answer` in markdown for easy scanning. Use `###` for main sections and `####` for sub-sections
      (the answer is displayed under an "Answer" heading, so do NOT use `#` or `##`). Use bullet points,
      bold, italics, and code blocks where they aid clarity. Do NOT write a `Sources` section yourself — it is
      built for you from the sources you cite (see Citations).
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
    - Every provided context block begins with a header like `Source [3] — Academy: Getting Started for Traders`.
      The number in brackets (here `3`) is that block's citation id.
    - Cite a claim by writing ONLY that bare id token inline, right after the claim it supports — e.g. `[3]`.
      Do NOT write the label, the source name, a URL, or any markdown link: just the bracketed number. The real
      clickable link and the `Sources` list are built for you from the id.
      - CORRECT: `... social volume can signal a potential top. [3]`
      - WRONG (do not write the label or a link): `... a potential top. [Academy: Getting Started for Traders](...)`
      - WRONG (do not invent a URL): `... a potential top. (https://academy.santiment.net/...)`
    - Use ONLY ids that appear in a provided `Source [...]` header. Never invent an id, a label, or a URL, and
      never cite a block that was not provided.
    - Citation frequency — cite SPARINGLY, at the paragraph or section level, NOT after every sentence. Aim for
      about one citation per paragraph or per distinct claim: place the id once, on the sentence that carries the
      key fact, and move on. When several consecutive sentences rely on the same source, cite it once for the
      whole passage. Do not re-cite an id you already used unless it later supports a clearly different claim.
    - One source per claim — cite the SINGLE id that best supports a claim. Do not pile several ids after one
      sentence; attach two only when two distinct sources each independently establish that exact claim (rare).
    - List every id you cited in the `source_ids` output field.
    </Citations_And_Links>
    </Instructions>

    <Output_Format>
    - Return a JSON object with exactly these keys:
      - `answer`: the markdown answer described above, with inline `[id]` citations and NO `Sources` section.
      - `source_ids`: an array of the integer ids you cited in `answer` (empty if you cited none).
      - `financial_disclaimer`: a boolean, per the Not_Financial_Advice rules.
    - Output ONLY this JSON object — no prose, code fences, or commentary around it.
    </Output_Format>

    <User_Input>
    #{question}
    </User_Input>
    """

    {:ok, prompt}
  end
end
