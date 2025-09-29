defmodule Sanbase.Knowledge.Faq do
  import Ecto.Query

  alias Sanbase.Repo
  alias Sanbase.Knowledge.FaqEntry

  require Logger

  def list_entries do
    FaqEntry
    |> order_by(desc: :updated_at)
    |> preload([:tags])
    |> Repo.all()
  end

  def embed_all() do
    all_faqs_chunks =
      from(p in FaqEntry,
        select: [:id, :question, :answer_markdown]
      )
      |> Sanbase.Repo.all()
      |> Enum.chunk_every(50)

    chunks_count = length(all_faqs_chunks)

    all_faqs_chunks
    |> Enum.with_index()
    |> Enum.each(fn {faqs, index} ->
      Logger.info(
        "[FaqEmbedding] Embedding batch ##{index}/#{chunks_count} consisting of #{length(faqs)} FAQ entries"
      )

      embed_faqs_batch(faqs)

      Logger.info("[FaqEmbedding] Finished embedding batch of #{length(faqs)} FAQ entries")
    end)
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

  defp maybe_update_embedding({:ok, %FaqEntry{} = entry} = result) do
    Task.Supervisor.async_nolink(Sanbase.TaskSupervisor, fn ->
      do_update_embedding(entry)
    end)

    result
  end

  defp maybe_update_embedding({:error, _} = error), do: error

  defp do_update_embedding(%FaqEntry{} = entry) do
    case Sanbase.AI.Embedding.generate_embeddings([entry_to_embedding_text(entry)], 1536) do
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

  defp entry_to_embedding_text(%FaqEntry{} = entry) do
    """
    Question: #{entry.question}
    Answer: #{entry.answer_markdown}
    """
  end

  def embed_faqs_batch(faqs) when is_list(faqs) do
    chunks =
      faqs
      |> Enum.map(fn faq_entry ->
        {faq_entry, entry_to_embedding_text(faq_entry)}
      end)

    texts = Enum.map(chunks, fn {_faq_entry, text} -> text end)

    {:ok, embeddings} =
      Sanbase.AI.Embedding.generate_embeddings(texts, 1536)

    Enum.zip_with(chunks, embeddings, fn {%FaqEntry{} = faq_entry, _text_chunk}, embedding ->
      faq_entry
      |> Ecto.Changeset.change(%{embedding: embedding})
      |> Sanbase.Repo.update()
    end)
  end
end
