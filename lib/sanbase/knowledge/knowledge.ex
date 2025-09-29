defmodule Sanbase.Knowledge do
  alias Sanbase.Repo
  alias Sanbase.Knowledge.FaqEntry
  alias Sanbase.Knowledge.Faq
  import Ecto.Query

  def answer_question(user_input, options \\ []) do
    with {:ok, [embedding]} <- Sanbase.AI.Embedding.generate_embeddings([user_input], 1536),
         {:ok, prompt} <- build_prompt(user_input, embedding, options),
         {:ok, answer} <- Sanbase.OpenAI.Question.ask(prompt) do
      {:ok, answer}
    end
  end

  def smart_search(user_input, options) do
    with {:ok, [embedding]} <- Sanbase.AI.Embedding.generate_embeddings([user_input], 1536),
         {:ok, faq_entries} <- maybe_find_most_similar_faqs(embedding, options),
         {:ok, academy_chunks} <- maybe_find_most_similar_academy_chunks(user_input, options),
         {:ok, insight_chunks} <- maybe_find_most_similar_insights(embedding, options),
         {:ok, answer} <- build_smart_search_result(faq_entries, academy_chunks, insight_chunks) do
      {:ok, answer}
    end
  end

  # Private functions

  defp build_smart_search_result(faq_entries, academy_chunks, insight_chunks) do
    format_similarity = fn similarity ->
      if is_float(similarity),
        do: :erlang.float_to_binary(similarity, decimals: 2),
        else: "embedding missing"
    end

    faqs_text =
      Enum.map(faq_entries, fn chunk ->
        "- [#{format_similarity.(chunk.similarity)}] [#{chunk.question}](#{SanbaseWeb.Endpoint.admin_url()}/admin/faq/#{chunk.id})"
      end)
      |> Enum.join("\n")

    insights_texts =
      Enum.map(insight_chunks, fn chunk ->
        "- [#{format_similarity.(chunk.similarity)}] [#{chunk.post_title}](#{SanbaseWeb.Endpoint.insight_url(chunk.post_id)})"
      end)
      |> Enum.join("\n")

    academy_texts =
      Enum.map(academy_chunks, fn chunk ->
        "- [#{format_similarity.(chunk.similarity)}] [#{chunk.title}](#{chunk.url})"
      end)
      |> Enum.join("\n")

    answer = """
    FAQs:
    #{faqs_text}

    Insights:
    #{insights_texts}

    Academy:
    #{academy_texts}
    """

    {:ok, answer}
  end

  defp build_prompt(user_input, embedding, options) do
    with {:ok, prompt} <- generate_initial_prompt(user_input),
         {:ok, prompt} <- maybe_add_similar_faqs(prompt, embedding, options),
         {:ok, prompt} <- maybe_add_similar_insight_chunks(prompt, embedding, options),
         {:ok, prompt} <- maybe_add_similar_academy_chunks(prompt, user_input, options) do
      {:ok, prompt}
    else
      unexpected ->
        raise(ArgumentError, "Got #{unexpected}")
    end
  end

  def maybe_add_similar_faqs(prompt, embedding, options) do
    if Keyword.get(options, :faq, true) do
      {:ok, faq_entries} = find_most_similar_faqs(embedding, 5)

      entries_text =
        Enum.map(faq_entries, fn faq_entry ->
          """
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

      {:ok, prompt}
    else
      {:ok, prompt}
    end
  end

  defp maybe_find_most_similar_faqs(embedding, options) do
    if Keyword.get(options, :faq, true) do
      find_most_similar_faqs(embedding, 5)
    else
      {:ok, []}
    end
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

  def maybe_add_similar_insight_chunks(prompt, embedding, options) do
    if Keyword.get(options, :insights, true) do
      with {:ok, post_embeddings} <- find_most_similar_insight_chunks(embedding, 5) do
        text_chunks = Enum.map(post_embeddings, & &1.text_chunk) |> Enum.join("\n\n")

        prompt =
          prompt <>
            """
            <Most_Similar_Santiment_Insight_Chunks>
            #{text_chunks}
            </Most_Similar_Santiment_Insight_Chunks>
            """

        {:ok, prompt}
      end
    else
      {:ok, prompt}
    end
  end

  defp maybe_find_most_similar_academy_chunks(embedding, options) do
    if Keyword.get(options, :academy, true) do
      find_most_similar_academy_chunks(embedding, 5)
    else
      {:ok, []}
    end
  end

  def find_most_similar_academy_chunks(user_input, size) do
    Sanbase.Knowledge.Academy.search(user_input, size)
  end

  def maybe_add_similar_academy_chunks(prompt, user_input, options \\ []) do
    if Keyword.get(options, :academy, true) do
      case find_most_similar_academy_chunks(user_input, 5) do
        {:ok, academy_chunks} ->
          academy_text_chunks =
            Enum.map(academy_chunks, fn academy_chunk ->
              """
              Article title: #{academy_chunk.title}
              Article URL: #{academy_chunk.url}
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

          {:ok, prompt}

        _ ->
          {:ok, prompt}
      end
    else
      {:ok, prompt}
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
    </Instructions>

    <User_Input>
    #{question}
    </User_Input>
    """

    {:ok, prompt}
  end
end
