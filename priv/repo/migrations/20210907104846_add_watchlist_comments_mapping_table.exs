defmodule Sanbase.Repo.Migrations.AddWatchlistCommentsMappingTable do
  use Ecto.Migration

  @table :watchlist_comments_mapping
  def change do
    create(table(@table)) do
      add(:comment_id, references(:comments, on_delete: :delete_all))
      add(:watchlist_id, references(:user_lists, on_delete: :delete_all))

      timestamps()
    end

    # A comment belongs to at most one post.
    # A post can have many comments (so it's not unique_index)
    create(unique_index(@table, [:comment_id]))
    create(index(@table, [:watchlist_id]))
  end
end
