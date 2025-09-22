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
    Repo.delete(entry)
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
  def maybe_add_similar_insight_chunks(prompt, embedding, options) do
    if Keyword.get(options, :insights, true) do
      with {:ok, post_embeddings} <-
             Sanbase.Insight.Post.find_most_similar_insight_chunks(embedding, 5) do
        text_chunks =
          Enum.map(post_embeddings, & &1.text_chunk)
          |> Enum.join("\n\n")

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

  def maybe_add_similar_academy_chunks(prompt, user_input, options \\ []) do
    if Keyword.get(options, :academy, true) do
      case Sanbase.AI.AcademyAIService.search_academy_simple(user_input, 5) do
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
    You are an expert Support Specialist working at Santiment. You have extensive experience in crypto, programming, trading, technical and non-technical support.
    You possess exceptional communication skills and can explain complex technical concepts in simple terms.
    Your goal is to give a clear and precise answer that best answers the User Input.
    </Role>

    <Instructions>
    1. Use the provided FAQ entries to answer the user's question.
    2. Be brief, professional and on point. Skip any introduction, greetings, congratulations.
    3. If you are not able to provide an answer based on the provided FAQ entries, just say that you cannot answer this question
    4. Format your answer in markdown. Use lists, headings, bold and italics if necessary. When providing links, use the markdown syntax for links.
    5. For code, use code blocks.
    6. If something looks similar, but not exactly the same, generate an answer that gives this answer. Be specific that this answer is taken from a slightly different context. Suggest contacting Santiment Support for further clarifications.
    </Instructions>

    <User_Input>
    Question: #{question}
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
