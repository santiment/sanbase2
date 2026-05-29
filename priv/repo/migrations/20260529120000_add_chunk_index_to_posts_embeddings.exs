defmodule Sanbase.Repo.Migrations.AddChunkIndexToPostsEmbeddings do
  use Ecto.Migration

  # The Unchunker reassembles adjacent chunks of the same entity, so it needs
  # them in document order. Academy chunks already store chunk_index;
  # posts_embeddings did not. Nullable: existing rows fall back to insertion
  # (id) order until re-embedded.
  def change do
    alter table(:posts_embeddings) do
      add(:chunk_index, :integer)
    end
  end
end
