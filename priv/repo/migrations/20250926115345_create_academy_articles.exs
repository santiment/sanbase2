defmodule Sanbase.Repo.Migrations.CreateAcademyArticles do
  use Ecto.Migration

  def change do
    create table(:academy_articles) do
      add(:github_path, :text, null: false)
      add(:academy_url, :text, null: false)
      add(:title, :text, null: false)
      add(:content_sha, :string, null: false)
      add(:is_stale, :boolean, default: false, null: false)

      timestamps()
    end

    create(unique_index(:academy_articles, [:github_path]))
    create(unique_index(:academy_articles, [:academy_url]))

    create table(:academy_article_chunks) do
      add(:article_id, references(:academy_articles, on_delete: :delete_all), null: false)

      add(:chunk_index, :integer, null: false)
      add(:heading, :text)
      add(:content, :text, null: false)
      add(:embedding, :vector, size: 1536, null: false)
      add(:is_stale, :boolean, default: false, null: false)

      timestamps()
    end

    create(index(:academy_article_chunks, [:article_id]))
    create(unique_index(:academy_article_chunks, [:article_id, :chunk_index]))

    execute(
      "CREATE INDEX academy_article_chunks_embedding_index ON academy_article_chunks USING hnsw (embedding vector_cosine_ops) WHERE is_stale = false",
      "DROP INDEX IF EXISTS academy_article_chunks_embedding_index"
    )
  end
end
