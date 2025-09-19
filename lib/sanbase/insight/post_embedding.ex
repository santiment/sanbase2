defmodule Sanbase.Insight.PostEmbedding do
  use Ecto.Schema
  import Ecto.Query
  import Ecto.Changeset

  schema "posts_embeddings" do
    field(:embedding, Pgvector.Ecto.Vector)
    belongs_to(:post, Sanbase.Insight.Post)

    timestamps()
  end

  @doc false
  def changeset(post_embedding, attrs) do
    post_embedding
    |> cast(attrs, [:post_id, :embedding])
    |> validate_required([:post_id, :embedding])
  end

  def embed_post(%Sanbase.Insight.Post{id: post_id, title: title, text: text}) do
    markdown = Htmd.convert!(text)
    chunks = TextChunker.split(markdown, chunk_size: 2000, chunk_overlap: 200, format: :markdown)

    chunk_texts = [title] ++ Enum.map(chunks, &String.trim(&1.text))

    case Sanbase.OpenAI.Embedding.generate_embedding(chunk_texts, 1536) do
      {:ok, embeddings} ->
        Sanbase.Repo.delete_all(from(pe in __MODULE__, where: pe.post_id == ^post_id))

        data =
          embeddings
          |> Enum.map(fn embedding ->
            %{embedding: embedding, post_id: post_id}
          end)

        Sanbase.Repo.insert_all(__MODULE__, data)

      {:error, reason} ->
        IO.inspect(reason, label: "Error generating embedding for post #{post_id}")
    end
  end
end
