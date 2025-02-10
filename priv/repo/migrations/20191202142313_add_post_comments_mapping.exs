defmodule Sanbase.Repo.Migrations.AddPostCommentsMapping do
  @moduledoc false
  use Ecto.Migration

  @table :post_comments_mapping
  def change do
    create(table(@table)) do
      add(:comment_id, references(:comments, on_delete: :delete_all))
      add(:post_id, references(:posts, on_delete: :delete_all))

      timestamps()
    end

    # A comment belongs to at most one post.
    # A post can have many comments (so it's not unique_index)
    create(unique_index(@table, [:comment_id]))
    create(index(@table, [:post_id]))
  end
end
