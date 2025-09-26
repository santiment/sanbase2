defmodule Sanbase.Knowledge.AcademyArticle do
  use Ecto.Schema

  import Ecto.Changeset

  alias Sanbase.Knowledge.AcademyArticleChunk

  schema "academy_articles" do
    field(:github_path, :string)
    field(:academy_url, :string)
    field(:title, :string)
    field(:content_sha, :string)
    field(:is_stale, :boolean, default: false)

    has_many(:chunks, AcademyArticleChunk, foreign_key: :article_id)

    timestamps()
  end

  @type t :: %__MODULE__{
          id: integer() | nil,
          github_path: String.t() | nil,
          academy_url: String.t() | nil,
          title: String.t() | nil,
          content_sha: String.t() | nil,
          is_stale: boolean() | nil,
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  @doc """
  Build changeset for creating/updating academy articles.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(article, attrs) do
    article
    |> cast(attrs, [:github_path, :academy_url, :title, :content_sha, :is_stale])
    |> validate_required([:github_path, :academy_url, :title, :content_sha])
    |> validate_format(:academy_url, ~r/^https?:\/\//)
    |> unique_constraint(:github_path)
    |> unique_constraint(:academy_url)
  end
end
