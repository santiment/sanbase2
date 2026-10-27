defmodule Sanbase.Knowledge.Faq do
  import Ecto.Query

  alias Sanbase.Accounts.User
  alias Sanbase.Repo
  alias Sanbase.Knowledge.FaqEntry

  require Logger

  # Entries at least this similar (on question + answer) count as duplicates. A
  # starting point; tune it once real drafts come in.
  @duplicate_min_similarity 0.85

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

  @doc """
  List non-deleted entries, newest first. `opts[:status]` (`:published` or
  `:draft`) narrows the list to that status; without it all statuses are listed.
  """
  def list_entries(page, page_size, opts \\ [])
      when is_integer(page) and is_integer(page_size) do
    page = if page < 1, do: 1, else: page
    offset = (page - 1) * page_size

    FaqEntry
    |> where([fe], fe.is_deleted == false)
    |> maybe_filter_status(Keyword.get(opts, :status))
    |> order_by(desc: :updated_at)
    |> preload([:tags, :created_by])
    |> limit(^page_size)
    |> offset(^offset)
    |> Repo.all()
  end

  def count_entries(opts \\ []) do
    FaqEntry
    |> where([fe], fe.is_deleted == false)
    |> maybe_filter_status(Keyword.get(opts, :status))
    |> Repo.aggregate(:count, :id)
  end

  def get_entry!(id) do
    Repo.get!(FaqEntry, id) |> Repo.preload([:tags, :created_by, :reviewed_by])
  end

  @doc """
  Fetch a non-deleted entry by id. Drafts are returned too: callers decide
  whether a draft may be shown.
  """
  @spec get_entry(String.t()) :: {:ok, %FaqEntry{}} | {:error, :not_found}
  def get_entry(id) when is_binary(id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         %FaqEntry{is_deleted: false} = entry <- Repo.get(FaqEntry, uuid) do
      {:ok, Repo.preload(entry, [:tags, :created_by, :reviewed_by])}
    else
      _ -> {:error, :not_found}
    end
  end

  def get_entry(_id), do: {:error, :not_found}

  def create_entry(attrs \\ %{}) do
    %FaqEntry{}
    |> FaqEntry.changeset(attrs)
    |> Repo.insert()
    |> maybe_update_embedding(true)
  end

  @doc """
  Create an unreviewed draft on behalf of `user`. Drafts never reach answers
  until `publish/2`.

  The draft is embedded before it is saved, so a duplicate check made right
  after already sees it. Unless `force: true` is given, near-duplicates of the
  draft (published entries or other drafts) are returned as
  `{:duplicates, entries}` and nothing is saved.
  """
  @spec create_draft(User.t(), map(), keyword()) ::
          {:ok, %FaqEntry{}}
          | {:duplicates, [map()]}
          | {:error, Ecto.Changeset.t() | :embedding_failed}
  def create_draft(%User{} = user, attrs, opts \\ []) do
    changeset =
      %FaqEntry{
        status: :draft,
        origin: Keyword.get(opts, :origin, :mcp),
        created_by_id: user.id,
        tags: []
      }
      |> FaqEntry.changeset(attrs)

    with :ok <- validate_changeset(changeset),
         {:ok, embedding} <- embed_changeset(changeset),
         :ok <- check_duplicates(embedding, Keyword.get(opts, :force, false)) do
      changeset
      |> Ecto.Changeset.put_change(:embedding, embedding)
      |> Repo.insert()
    end
  end

  @doc """
  Update a draft. The row is locked and must still be an undeleted draft, so an
  edit racing a publish can never change live content. A changed question or
  answer is re-embedded before the update is saved.
  """
  @spec update_draft(%FaqEntry{}, map()) ::
          {:ok, %FaqEntry{}} | {:error, :not_a_draft | :embedding_failed | Ecto.Changeset.t()}
  def update_draft(%FaqEntry{id: id}, attrs) do
    Repo.transaction(fn ->
      with %FaqEntry{} = entry <- lock_draft(id),
           changeset = entry |> Repo.preload(:tags) |> FaqEntry.changeset(attrs),
           {:ok, changeset} <- maybe_put_embedding(changeset),
           {:ok, entry} <- Repo.update(changeset) do
        entry
      else
        nil -> Repo.rollback(:not_a_draft)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Publish a draft as reviewed by `reviewer`. `seen` is the entry as the
  reviewer saw it: the draft is published only if it still has that question,
  answer and source, so an edit made after the review never goes live unseen.

  Returns `{:error, :changed}` if the draft was edited in the meantime and
  `{:error, :not_a_draft}` if it was already published or rejected.
  """
  @spec publish(%FaqEntry{}, User.t()) ::
          {:ok, %FaqEntry{}} | {:error, :changed | :not_a_draft}
  def publish(%FaqEntry{id: id} = seen, %User{} = reviewer) do
    now = NaiveDateTime.utc_now(:second)

    {count, _} =
      from(e in FaqEntry,
        where:
          e.id == ^id and e.status == :draft and e.is_deleted == false and
            e.question == ^seen.question and e.answer_markdown == ^seen.answer_markdown and
            fragment("? IS NOT DISTINCT FROM ?", e.source_url, ^seen.source_url)
      )
      |> Repo.update_all(
        set: [status: :published, reviewed_by_id: reviewer.id, reviewed_at: now, updated_at: now]
      )

    case count do
      1 -> {:ok, get_entry!(id)}
      0 -> {:error, publish_failure_reason(id)}
    end
  end

  def update_entry(%FaqEntry{} = entry, attrs) do
    changeset = FaqEntry.changeset(entry, attrs)

    changeset
    |> Repo.update()
    |> maybe_update_embedding(content_changed?(changeset))
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

  @doc """
  Return the `size` entries most similar to `user_input` (text or embedding).

  Only published entries are searched by default, as the results feed answers.
  Pass `statuses: [:draft]` or `statuses: [:published, :draft]` to search
  drafts, e.g. for duplicate checks; each result carries its `:status`.
  """
  def find_most_similar_faqs(user_input, size, opts \\ [])

  def find_most_similar_faqs(user_input, size, opts) when is_binary(user_input) do
    with {:ok, [embedding]} <- Sanbase.AI.Embedding.generate_embeddings([user_input], 1536),
         {:ok, result} <- find_most_similar_faqs(embedding, size, opts) do
      {:ok, result}
    end
  end

  def find_most_similar_faqs(embedding, size, opts) when is_list(embedding) do
    query =
      from(
        e in entries_query(Keyword.get(opts, :statuses, [:published])),
        order_by: fragment("embedding <=> ?", ^embedding),
        limit: ^size,
        select: %{
          id: e.id,
          question: e.question,
          answer_markdown: e.answer_markdown,
          status: e.status,
          similarity: fragment("1 - (embedding <=> ?)", ^embedding)
        }
      )

    result = Sanbase.Repo.VectorQuery.all(query)
    {:ok, result}
  end

  @doc """
  The base query for every read that feeds answers, search or exports:
  published, non-deleted entries. Start such reads here so drafts cannot leak in.
  """
  def live_query(), do: entries_query([:published])

  # Private functions

  defp entries_query(statuses) do
    from(e in FaqEntry, where: e.is_deleted == false and e.status in ^statuses)
  end

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, status), do: where(query, [e], e.status == ^status)

  defp lock_draft(id) do
    from(e in FaqEntry,
      where: e.id == ^id and e.status == :draft and e.is_deleted == false,
      lock: "FOR UPDATE"
    )
    |> Repo.one()
  end

  defp publish_failure_reason(id) do
    case Repo.get(FaqEntry, id) do
      %FaqEntry{status: :draft, is_deleted: false} -> :changed
      _ -> :not_a_draft
    end
  end

  defp validate_changeset(%Ecto.Changeset{valid?: true}), do: :ok
  defp validate_changeset(changeset), do: {:error, changeset}

  defp check_duplicates(_embedding, true = _force), do: :ok

  defp check_duplicates(embedding, _force) do
    {:ok, entries} = find_most_similar_faqs(embedding, 3, statuses: [:published, :draft])

    case Enum.filter(
           entries,
           &(is_number(&1.similarity) and &1.similarity >= @duplicate_min_similarity)
         ) do
      [] -> :ok
      duplicates -> {:duplicates, duplicates}
    end
  end

  defp content_changed?(changeset) do
    Enum.any?([:question, :answer_markdown], &Map.has_key?(changeset.changes, &1))
  end

  defp maybe_put_embedding(changeset) do
    if content_changed?(changeset) do
      with {:ok, embedding} <- embed_changeset(changeset) do
        {:ok, Ecto.Changeset.put_change(changeset, :embedding, embedding)}
      end
    else
      {:ok, changeset}
    end
  end

  defp embed_changeset(changeset) do
    text =
      embedding_text(
        Ecto.Changeset.get_field(changeset, :question),
        Ecto.Changeset.get_field(changeset, :answer_markdown)
      )

    case Sanbase.AI.Embedding.generate_embeddings([text], 1536) do
      {:ok, [embedding]} -> {:ok, embedding}
      _ -> {:error, :embedding_failed}
    end
  end

  # In test the embedding runs inline, so it stays within the test's mocks and
  # Ecto sandbox instead of racing them from a detached task.
  if Application.compile_env(:sanbase, :env) == :test do
    defp maybe_update_embedding({:ok, %FaqEntry{} = entry} = result, true = _content_changed?) do
      do_update_embedding(entry)
      result
    end
  else
    defp maybe_update_embedding({:ok, %FaqEntry{} = entry} = result, true = _content_changed?) do
      Task.Supervisor.async_nolink(Sanbase.TaskSupervisor, fn ->
        do_update_embedding(entry)
      end)

      result
    end
  end

  defp maybe_update_embedding(result, _content_changed?), do: result

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
    embedding_text(entry.question, entry.answer_markdown)
  end

  defp embedding_text(question, answer_markdown) do
    """
    Question: #{question}
    Answer: #{answer_markdown}
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
