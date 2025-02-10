defmodule Sanbase.Repo.Migrations.AddOnDeletePostsTags do
  @moduledoc false
  use Ecto.Migration

  @table "posts_tags"

  def up do
    drop(unique_index(@table, [:post_id, :tag_id]))
    drop(constraint(@table, "posts_tags_post_id_fkey"))
    drop(constraint(@table, "posts_tags_tag_id_fkey"))

    alter table(@table) do
      modify(:post_id, references(:posts, on_delete: :delete_all))
      modify(:tag_id, references(:tags, on_delete: :delete_all))
    end
  end

  def down do
    drop(constraint(@table, "posts_tags_post_id_fkey"))
    drop(constraint(@table, "posts_tags_tag_id_fkey"))

    alter table(@table) do
      modify(:post_id, references(:posts))
      modify(:tag_id, references(:tags))
    end

    create(unique_index(@table, [:post_id, :tag_id]))
  end
end
