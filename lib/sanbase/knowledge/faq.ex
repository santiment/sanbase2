defmodule Sanbase.Knowledge.Faq do
  alias Sanbase.Repo
  alias Sanbase.Knowledge.FaqEntry
  import Ecto.Query

  def list_entries do
    FaqEntry
    |> order_by(desc: :updated_at)
    |> preload([:tags])
    |> Repo.all()
  end

  def list_entries(page, page_size) when is_integer(page) and is_integer(page_size) do
    page = if page < 1, do: 1, else: page
    offset = (page - 1) * page_size

    FaqEntry
    |> where([fe], fe.is_deleted == false)
    |> order_by(desc: :updated_at)
    |> preload([:tags])
    |> limit(^page_size)
    |> offset(^offset)
    |> Repo.all()
  end

  def count_entries do
    Repo.aggregate(FaqEntry, :count, :id)
  end

  def get_entry!(id) do
    Repo.get!(FaqEntry, id) |> Repo.preload(:tags)
  end

  def create_entry(attrs \\ %{}) do
    %FaqEntry{}
    |> FaqEntry.changeset(attrs)
    |> Repo.insert()
    |> maybe_update_embedding()
  end

  def update_entry(%FaqEntry{} = entry, attrs) do
    entry
    |> FaqEntry.changeset(attrs)
    |> Repo.update()
    |> maybe_update_embedding()
  end

  def delete_entry(%FaqEntry{} = entry) do
    changeset = Ecto.Changeset.change(entry, is_deleted: true)
    Repo.update(changeset)
  end

  def change_entry(%FaqEntry{} = entry, attrs \\ %{}) do
    entry =
      if Map.get(entry, :tags) == %Ecto.Association.NotLoaded{},
        do: %{entry | tags: []},
        else: entry

    FaqEntry.changeset(entry, attrs)
  end

  def answer_question(user_input, options \\ []) do
    with {:ok, [embedding]} <- Sanbase.AI.Embedding.generate_embeddings([user_input], 1536),
         {:ok, prompt} <- build_prompt(user_input, embedding, options),
         {:ok, answer} <- Sanbase.OpenAI.Question.ask(prompt) do
      {:ok, answer}
    end
  end

  def smart_search(user_input, options \\ []) do
    with {:ok, [embedding]} <- Sanbase.AI.Embedding.generate_embeddings([user_input], 1536),
         {:ok, faq_entries} <- find_most_similar_faqs(embedding, Keyword.get(options, :size, 5)),
         {:ok, academy_chunks} <- find_most_similar_academy_chunks(user_input, options),
         {:ok, insight_chunks} <- find_most_similar_insights(embedding, options),
         {:ok, answer} <-
           build_smart_search_result(user_input, faq_entries, academy_chunks, insight_chunks) do
      {:ok, answer}
    end
  end

  # Private functions

  defp build_smart_search_result(user_input, faq_entries, academy_chunks, insight_chunks) do
    format_similarity = fn float ->
      :erlang.float_to_binary(float, decimals: 2)
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

  def find_most_similar_faqs(user_input, size) when is_binary(user_input) do
    with {:ok, [embedding]} <- Sanbase.AI.Embedding.generate_embeddings([user_input], 1536),
         {:ok, result} <- find_most_similar_faqs(embedding, size) do
      {:ok, result}
    end
  end

  def find_most_similar_faqs(embedding, size) when is_list(embedding) do
    query =
      from(
        e in FaqEntry,
        where: e.is_deleted == false,
        order_by: fragment("embedding <=> ?", ^embedding),
        limit: ^size,
        select: %{
          id: e.id,
          question: e.question,
          answer_markdown: e.answer_markdown,
          similarity: fragment("1 - (embedding <=> ?)", ^embedding)
        }
      )

    result = Repo.all(query)
    {:ok, result}
  end

  # Private functions
  defp find_most_similar_insight_chunks(embedding, size) do
    Sanbase.Insight.Post.find_most_similar_insight_chunks(embedding, 5)
  end

  defp find_most_similar_insights(embedding, size) do
    Sanbase.Insight.Post.find_most_similar_insights(embedding, 5)
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

  def find_most_similar_academy_chunks(user_input, options) do
    Sanbase.AI.AcademyAIService.search_academy_simple(user_input, 5)
  end

  def maybe_add_similar_academy_chunks(prompt, user_input, options \\ []) do
    if Keyword.get(options, :academy, true) do
      case find_most_similar_academy_chunks(user_input, 5) do
        {:ok, academy_chunks} ->
          academy_text_chunks =
            Enum.map(academy_chunks, fn academy_chunk ->
              """
              Article title: #{academy_chunk.title}
              Most relevant chunk from article: #{academy_chunk.text_chunk}
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

  defp maybe_update_embedding({:ok, %FaqEntry{} = entry} = result) do
    Task.Supervisor.async_nolink(Sanbase.TaskSupervisor, fn ->
      do_update_embedding(entry)
    end)

    result
  end

  defp maybe_update_embedding({:error, _} = error), do: error

  defp do_update_embedding(%FaqEntry{} = entry) do
    text = """
    Question: #{entry.question}
    Answer: #{entry.answer_markdown}
    """

    case Sanbase.AI.Embedding.generate_embeddings([text], 1536) do
      {:ok, [embedding]} ->
        entry
        |> Ecto.Changeset.change(embedding: embedding)
        |> Repo.update()
        |> case do
          {:ok, updated_entry} -> {:ok, updated_entry}
          {:error, _} -> {:ok, entry}
        end

      {:error, _} ->
        {:ok, entry}
    end
  end
end
