defmodule Sanbase.Insight.PostEmbedding do
  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset

  alias Sanbase.Insight.Post

  require(Logger)

  # Marker line separating the title preamble from the chunk body in the stored
  # `text_chunk`. Exposed so context expansion strips the preamble with the same
  # constant the writer uses, instead of re-declaring the literal string.
  @chunk_text_marker "Chunk text from the insight:"

  @doc false
  def chunk_text_marker(), do: @chunk_text_marker

  schema "posts_embeddings" do
    field(:embedding, Pgvector.Ecto.Vector)
    field(:text_chunk, :string)
    field(:chunk_index, :integer)
    belongs_to(:post, Post)

    timestamps()
  end

  @doc false
  def changeset(post_embedding, attrs) do
    post_embedding
    |> cast(attrs, [:post_id, :embedding, :text_chunk, :chunk_index])
    |> validate_required([:post_id, :embedding, :text_chunk])
  end

  def embed_all_posts() do
    all_published_posts =
      from(p in Post,
        where: p.ready_state == ^Post.published(),
        select: [:id, :title, :text]
      )
      |> Sanbase.Repo.all()

    published_posts_chunks =
      all_published_posts
      |> Enum.chunk_every(50)

    chunks_count = length(published_posts_chunks)

    published_posts_chunks
    |> Enum.with_index()
    |> Enum.each(fn {posts, index} ->
      Logger.info(
        "[PostEmbedding] Embedding batch ##{index}/#{chunks_count} consisting of #{length(posts)} posts"
      )

      # Log and skip a failing batch rather than aborting the whole reindex. A DB
      # error inside the transaction raises, so rescue in addition to matching the
      # {:error, _} rollback case.
      try do
        case embed_posts_batch(posts) do
          {:ok, _} ->
            Logger.info(
              "[PostEmbedding] Finished embedding batch ##{index} of #{length(posts)} posts"
            )

          {:error, reason} ->
            Logger.error("[PostEmbedding] Embedding batch ##{index} failed: #{inspect(reason)}")
        end
      rescue
        e ->
          Logger.error(
            "[PostEmbedding] Embedding batch ##{index} crashed: #{Exception.message(e)}"
          )
      end
    end)
  end

  def drop_post_embeddings(%Sanbase.Insight.Post{id: post_id}) do
    from(pe in __MODULE__, where: pe.post_id == ^post_id)
    |> Sanbase.Repo.delete_all()
  end

  @doc """
  Delete embeddings whose post is no longer published. `embed_all_posts/0` only
  ever (re)embeds published posts, so once a post is unpublished its embeddings
  are otherwise never removed. Uses the same "published" predicate as
  `embed_all_posts/0` so the kept set and the embedded set stay in sync.

  The keep set is expressed as a subquery, so the pruning happens in a single
  DB statement instead of marshalling every published id into the app.

  Returns the number of deleted rows.
  """
  def prune_all_stale() do
    published_ids = from(p in Post, where: p.ready_state == ^Post.published(), select: p.id)

    {deleted, _} =
      from(pe in __MODULE__, where: pe.post_id not in subquery(published_ids))
      |> Sanbase.Repo.delete_all()

    Logger.info("[PostEmbedding] Pruned #{deleted} stale insight embeddings")

    deleted
  end

  @doc """
  Fetch the chunks of `post_id` whose `chunk_index` is in `indices`, ordered by
  `chunk_index`. Used by context expansion to pull the neighbours around a
  matched chunk.
  """
  def fetch_chunks(post_id, indices) when is_integer(post_id) and is_list(indices) do
    from(pe in __MODULE__,
      where: pe.post_id == ^post_id and pe.chunk_index in ^indices,
      order_by: [asc: pe.chunk_index],
      select: %{chunk_index: pe.chunk_index, text_chunk: pe.text_chunk}
    )
    |> Sanbase.Repo.all()
  end

  def embed_post(%Sanbase.Insight.Post{} = post) do
    embed_posts_batch([post])
  end

  def embed_posts_batch(posts) when is_list(posts) do
    chunks =
      posts
      |> Enum.reject(fn %{text: text} -> String.length(text || "") < 10 end)
      |> Enum.flat_map(fn post ->
        markdown = Htmd.convert!(post.text)

        markdown
        |> TextChunker.split(chunk_size: 2000, chunk_overlap: 200, format: :markdown)
        |> Enum.with_index()
        |> Enum.map(fn {chunk, chunk_index} ->
          text_chunk = """
          Insight Title:
          #{post.title}

          #{@chunk_text_marker}
          #{String.trim(chunk.text)}
          """

          # chunk_index records document order so the Unchunker can reassemble
          # adjacent chunks of the same post.
          %{post_id: post.id, text_chunk: text_chunk, chunk_index: chunk_index}
        end)
      end)

    chunk_texts = Enum.map(chunks, fn %{text_chunk: text} -> text end)

    {:ok, embeddings} =
      Sanbase.AI.Embedding.generate_embeddings(chunk_texts, 1536)

    post_ids = Enum.map(posts, & &1.id)

    data =
      Enum.zip_with(chunks, embeddings, fn chunk, embedding ->
        %{
          embedding: embedding,
          post_id: chunk.post_id,
          text_chunk: chunk.text_chunk,
          chunk_index: chunk.chunk_index,
          inserted_at: NaiveDateTime.utc_now(:second),
          updated_at: NaiveDateTime.utc_now(:second)
        }
      end)

    # Replace this batch's embeddings atomically: a crash between the delete and
    # the insert would otherwise leave these posts with their old rows gone and
    # the new ones not yet written. Embeddings are generated above, before the
    # transaction, so the slow API call never holds the transaction open.
    Sanbase.Repo.transaction(fn ->
      Sanbase.Repo.delete_all(from(pe in __MODULE__, where: pe.post_id in ^post_ids))
      Sanbase.Repo.insert_all(__MODULE__, data)
    end)
  end
end
