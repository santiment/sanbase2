defmodule Sanbase.Knowledge.AcademyArticle do
  use Ecto.Schema

  import Ecto.Changeset

  alias Sanbase.Knowledge.AcademyArticleChunk

  schema "academy_articles" do
    field(:github_path, :string)
    field(:academy_url, :string)
    field(:title, :string)
    field(:content_sha, :string)
    field(:index_version, :integer, default: 0)
    field(:is_stale, :boolean, default: false)
    # Set only by `Sanbase.Knowledge.AcademyQuestions.generate/1`, never by the reindex.
    field(:suggested_questions, {:array, :string}, default: [])
    field(:questions_content_sha, :string)

    has_many(:chunks, AcademyArticleChunk, foreign_key: :article_id)

    timestamps()
  end

  @type t :: %__MODULE__{
          id: integer() | nil,
          github_path: String.t() | nil,
          academy_url: String.t() | nil,
          title: String.t() | nil,
          content_sha: String.t() | nil,
          index_version: integer() | nil,
          is_stale: boolean() | nil,
          suggested_questions: [String.t()],
          questions_content_sha: String.t() | nil,
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  @doc """
  Build changeset for creating/updating academy articles.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(article, attrs) do
    article
    |> cast(attrs, [:github_path, :academy_url, :title, :content_sha, :index_version, :is_stale])
    |> validate_required([:github_path, :academy_url, :title, :content_sha])
    |> validate_format(:academy_url, ~r/^https?:\/\//)
    |> unique_constraint(:github_path)
    |> unique_constraint(:academy_url)
  end

  @doc """
  Changeset for the generated autocomplete questions. Kept apart from
  `changeset/2` so a reindex never overwrites them.
  """
  @spec questions_changeset(t(), [String.t()]) :: Ecto.Changeset.t()
  def questions_changeset(article, questions) do
    change(article, suggested_questions: questions, questions_content_sha: article.content_sha)
  end
end
