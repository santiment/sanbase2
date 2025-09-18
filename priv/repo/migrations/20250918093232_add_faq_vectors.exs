defmodule Sanbase.Repo.Migrations.AddFaqVectors do
  use Ecto.Migration

  def change do
    alter table(:faq_entries) do
      add(:embedding, :vector, size: 1536)
    end

    create(
      index(:faq_entries, ["embedding vector_cosine_ops"],
        using: :hnsw,
        name: :faq_entities_embedding_index
      )
    )
  end
end
