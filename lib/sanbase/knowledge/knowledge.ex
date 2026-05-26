defmodule Sanbase.Knowledge do
  @default_min_similarity 0.35
  @no_answer_message "I don't have enough information in the available Santiment FAQ, Academy, or Insights content to answer this question. Please contact Santiment Support for further assistance."

  def answer_question(user_input, options \\ []) do
    with {:ok, [embedding]} <- Sanbase.AI.Embedding.generate_embeddings([user_input], 1536),
         {:ok, prompt, sources_found?} <-
           build_question_answer_prompt(user_input, embedding, options) do
      if sources_found? do
        Sanbase.OpenAI.Question.ask(prompt)
      else
        {:ok, @no_answer_message}
      end
    end
  end

  def smart_search(user_input, options) do
    min_sim = min_similarity(options)

    with {:ok, [embedding]} <- Sanbase.AI.Embedding.generate_embeddings([user_input], 1536),
         {:ok, faq_entries} <- maybe_find_most_similar_faqs(embedding, options),
         {:ok, academy_articles} <- maybe_find_most_similar_academy_articles(embedding, options),
         {:ok, insights} <- maybe_find_most_similar_insights(embedding, options) do
      filtered_faqs = filter_by_similarity(faq_entries, min_sim)
      filtered_academy = filter_by_similarity(academy_articles, min_sim)
      filtered_insights = filter_by_similarity(insights, min_sim)

      if filtered_faqs == [] and filtered_academy == [] and filtered_insights == [] do
        {:ok, @no_answer_message}
      else
        build_smart_search_result(filtered_faqs, filtered_academy, filtered_insights, options)
      end
    end
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
           maybe_add_similar_faqs(prompt, embedding, options, min_sim),
         {:ok, prompt, insights_found?} <-
           maybe_add_similar_insight_chunks(prompt, embedding, options, min_sim),
         {:ok, prompt, academy_found?} <-
           maybe_add_similar_academy_chunks(prompt, embedding, options, min_sim) do
      {:ok, prompt, faq_found? or insights_found? or academy_found?}
    end
  end

  defp maybe_add_similar_faqs(prompt, embedding, options, min_sim) do
    if Keyword.get(options, :faq, true) do
      with {:ok, faq_entries} <- find_most_similar_faqs(embedding, 5) do
        faq_entries = filter_by_similarity(faq_entries, min_sim)

        if faq_entries == [] do
          {:ok, prompt, false}
        else
          entries_text =
            Enum.map(faq_entries, fn faq_entry ->
              """
              Source: [FAQ:#{faq_entry.id}]
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

  defp maybe_find_most_similar_faqs(embedding, options) do
    if Keyword.get(options, :faq, true) do
      find_most_similar_faqs(embedding, 5)
    else
      {:ok, []}
    end
  end

  defp min_similarity(options) do
    Keyword.get(options, :min_similarity, @default_min_similarity)
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

  defp maybe_find_most_similar_insights(embedding, options) do
    if Keyword.get(options, :insights, true) do
      find_most_similar_insights(embedding, 5)
    else
      {:ok, []}
    end
  end

  defp find_most_similar_insights(embedding, size) do
    Sanbase.Insight.Post.find_most_similar_insights(embedding, size)
  end

  defp maybe_add_similar_insight_chunks(prompt, embedding, options, min_sim) do
    if Keyword.get(options, :insights, true) do
      with {:ok, post_embeddings} <- find_most_similar_insight_chunks(embedding, 5) do
        post_embeddings = filter_by_similarity(post_embeddings, min_sim)

        if post_embeddings == [] do
          {:ok, prompt, false}
        else
          text_chunks =
            Enum.map(post_embeddings, fn chunk ->
              """
              Source: [Insight:#{chunk.post_id}] "#{chunk.post_title}"
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

  defp maybe_find_most_similar_academy_articles(embedding, options) do
    if Keyword.get(options, :academy, true) do
      Sanbase.Knowledge.Academy.search_articles(embedding, 5)
    else
      {:ok, []}
    end
  end

  defp maybe_add_similar_academy_chunks(prompt, embedding, options, min_sim) do
    if Keyword.get(options, :academy, true) do
      case Sanbase.Knowledge.Academy.search_chunks(embedding, 5) do
        {:ok, academy_chunks} ->
          academy_chunks = filter_by_similarity(academy_chunks, min_sim)

          if academy_chunks == [] do
            {:ok, prompt, false}
          else
            academy_text_chunks =
              Enum.map(academy_chunks, fn academy_chunk ->
                """
                Source: [Academy:#{academy_chunk.url}]
                Article title: #{academy_chunk.title}
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
    11. Cite every claim with the source markers exactly as provided: `[FAQ:<id>]`, `[Academy:<url>]`, or `[Insight:<id>]`.
        Place the marker inline immediately after the sentence or bullet it supports. Do not invent markers and do not omit them.
    12. End the answer with a `Sources` section listing each unique cited marker on its own bullet.
    </Instructions>

    <User_Input>
    #{question}
    </User_Input>
    """

    {:ok, prompt}
  end
end
