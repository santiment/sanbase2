defmodule Sanbase.Repo.Migrations.CreatePostsTagsLinkTable do
  use Ecto.Migration

  def change do
    create table(:posts_tags) do
      add(:post_id, references(:posts))
      add(:tag_id, references(:tags))
    end

    create(unique_index(:posts_tags, [:post_id, :tag_id]))
  end
end
