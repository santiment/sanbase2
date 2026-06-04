defmodule Sanbase.Knowledge.AcademyArticleChunk do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Knowledge.AcademyArticle

  schema "academy_article_chunks" do
    field(:chunk_index, :integer)
    field(:heading, :string)
    field(:content, :string)
    field(:embedding, Pgvector.Ecto.Vector)
    field(:is_stale, :boolean, default: false)

    belongs_to(:article, AcademyArticle, foreign_key: :article_id)

    timestamps()
  end

  @type t :: %__MODULE__{
          id: integer() | nil,
          article_id: integer() | nil,
          chunk_index: integer() | nil,
          heading: String.t() | nil,
          content: String.t() | nil,
          embedding: Pgvector.Ecto.Vector.t() | nil,
          is_stale: boolean() | nil,
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  @doc """
  Build changeset for academy article chunks.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(chunk, attrs) do
    chunk
    |> cast(attrs, [:article_id, :chunk_index, :heading, :content, :embedding, :is_stale])
    |> validate_required([:article_id, :chunk_index, :content, :embedding])
    |> foreign_key_constraint(:article_id)
    |> unique_constraint([:article_id, :chunk_index])
  end

  @doc """
  Fetch the non-stale chunks of `article_id` whose `chunk_index` is in
  `indices`, ordered by `chunk_index`. Used by context expansion to pull the
  neighbours around a matched chunk.
  """
  def fetch_chunks(article_id, indices) when is_integer(article_id) and is_list(indices) do
    from(c in __MODULE__,
      where: c.article_id == ^article_id and c.chunk_index in ^indices and c.is_stale == false,
      order_by: [asc: c.chunk_index],
      select: %{chunk_index: c.chunk_index, content: c.content}
    )
    |> Sanbase.Repo.all()
  end
end
