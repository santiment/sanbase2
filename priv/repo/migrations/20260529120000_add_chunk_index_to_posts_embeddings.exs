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

    # Chunk order must be deterministic: a non-negative index, and at most one
    # row per (post_id, chunk_index) so reassembly never sees duplicates. The
    # checks only apply to populated rows; legacy NULLs are left untouched.
    create(
      constraint(:posts_embeddings, :posts_embeddings_chunk_index_non_negative,
        check: "chunk_index IS NULL OR chunk_index >= 0"
      )
    )

    create(
      unique_index(:posts_embeddings, [:post_id, :chunk_index],
        where: "chunk_index IS NOT NULL",
        name: :posts_embeddings_post_id_chunk_index_index
      )
    )
  end
end
