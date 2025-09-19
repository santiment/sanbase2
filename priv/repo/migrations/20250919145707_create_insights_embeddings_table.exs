defmodule Sanbase.Repo.Migrations.CreateInsightsEmbeddingsTable do
  use Ecto.Migration

  def change do
    create table(:posts_embeddings) do
      add(:post_id, references(:posts, on_delete: :delete_all), null: false)
      add(:embedding, :vector, size: 1536, null: false)
    end

    create(index(:posts_embeddings, [:post_id]))
  end
end
