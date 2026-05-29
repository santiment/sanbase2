defmodule Sanbase.Knowledge.AcademyArticleChunk do
  use Ecto.Schema

  import Ecto.Changeset

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
end
