defmodule Sanbase.Insight.PostEmbedding do
  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset

  alias Sanbase.Insight.Post

  require(Logger)

  schema "posts_embeddings" do
    field(:embedding, Pgvector.Ecto.Vector)
    field(:text_chunk, :string)
    belongs_to(:post, Post)

    timestamps()
  end

  @doc false
  def changeset(post_embedding, attrs) do
    post_embedding
    |> cast(attrs, [:post_id, :embedding, :text_chunk])
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

      embed_posts_batch(posts)

      Logger.info("[PostEmbedding] Finished embedding batch of #{length(posts)} posts")
    end)
  end

  def embed_posts_batch(posts) when is_list(posts) do
    chunks =
      posts
      |> Enum.reject(fn %{text: text} -> String.length(text || "") < 10 end)
      |> Enum.flat_map(fn post ->
        markdown = Htmd.convert!(post.text)

        chunks =
          TextChunker.split(markdown, chunk_size: 2000, chunk_overlap: 200, format: :markdown)

        Enum.map(chunks, fn chunk ->
          text_chunk = """
          Insight Title:
          #{post.title}

          Chunk text from the insight:
          #{String.trim(chunk.text)}
          """

          {post.id, text_chunk}
        end)
      end)

    chunk_texts = Enum.map(chunks, fn {_post_id, text} -> text end)

    {:ok, embeddings} =
      Sanbase.AI.Embedding.generate_embeddings(chunk_texts, 1536)

    post_ids = Enum.map(posts, & &1.id)
    Sanbase.Repo.delete_all(from(pe in __MODULE__, where: pe.post_id in ^post_ids))

    data =
      Enum.zip_with(chunks, embeddings, fn {post_id, text_chunk}, embedding ->
        %{
          embedding: embedding,
          post_id: post_id,
          text_chunk: text_chunk,
          inserted_at: NaiveDateTime.utc_now(:second),
          updated_at: NaiveDateTime.utc_now(:second)
        }
      end)

    Sanbase.Repo.insert_all(__MODULE__, data)
  end
end
