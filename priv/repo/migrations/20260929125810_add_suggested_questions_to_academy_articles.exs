defmodule Sanbase.Repo.Migrations.AddSuggestedQuestionsToAcademyArticles do
  use Ecto.Migration

  def change do
    alter table(:academy_articles) do
      add(:suggested_questions, {:array, :string}, null: false, default: [])
      # content_sha of the article when its questions were generated; a mismatch
      # means the article changed since and its questions may be stale.
      add(:questions_content_sha, :string)
    end
  end
end
