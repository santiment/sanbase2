defmodule Sanbase.Insight.PostEmbedding do
  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset

  alias Sanbase.Insight.Post

  require(Logger)

  schema "posts_embeddings" do
    field(:embedding, Pgvector.Ecto.Vector)
    belongs_to(:post, Post)

    timestamps()
  end

  @doc false
  def changeset(post_embedding, attrs) do
    post_embedding
    |> cast(attrs, [:post_id, :embedding])
    |> validate_required([:post_id, :embedding])
  end

  def embed_all_posts() do
    all_published_posts =
      from(p in Post,
        where: p.ready_state == ^Post.published(),
        select: [:id, :title, :text]
      )
      |> Sanbase.Repo.all()

    all_published_posts
    |> Enum.chunk_every(50)
    |> Enum.each(fn posts ->
      embed_posts_batch(posts)
    end)
  end

  def embed_posts_batch(posts) when is_list(posts) do
    chunks =
      Enum.flat_map(posts, fn post ->
        markdown = Htmd.convert!(post.text)

        chunks =
          TextChunker.split(markdown, chunk_size: 2000, chunk_overlap: 200, format: :markdown)

        [{post.id, post.title}] ++ Enum.map(chunks, &{post.id, String.trim(&1.text)})
      end)

    chunk_texts = Enum.map(chunks, fn {_post_id, text} -> text end)

    case Sanbase.AI.Embedding.generate_embeddings(chunk_texts, 1536) do
      {:ok, embeddings} ->
        post_ids = Enum.map(posts, & &1.id)
        Sanbase.Repo.delete_all(from(pe in __MODULE__, where: pe.post_id in ^post_ids))

        data =
          Enum.zip_with(chunks, embeddings, fn {post_id, _text}, embedding ->
            %{embedding: embedding, post_id: post_id}
          end)

        Sanbase.Repo.insert_all(__MODULE__, data)
    end
  end
end
