defmodule Sanbase.Repo.Migrations.AddChunkByteOffsets do
  use Ecto.Migration

  # Byte offsets of each chunk into the source markdown it was split from.
  # They let us "unchunk": reconstruct the original contiguous span between
  # the first picked chunk's start and the last picked chunk's end, which
  # removes the overlap duplication that naive chunk concatenation produces.
  #
  # For academy we also persist the source markdown so the span can be
  # sliced without refetching from GitHub. For insights the source markdown
  # is re-derived from `posts.text` at read time, so no parent column here.
  def change do
    alter table(:academy_article_chunks) do
      add(:start_byte, :integer)
      add(:end_byte, :integer)
    end

    alter table(:academy_articles) do
      add(:markdown, :text)
    end

    alter table(:posts_embeddings) do
      add(:start_byte, :integer)
      add(:end_byte, :integer)
    end
  end
end
