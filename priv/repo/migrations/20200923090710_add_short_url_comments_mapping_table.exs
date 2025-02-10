defmodule Sanbase.Repo.Migrations.AddShortUrlCommentsMappingTable do
  @moduledoc false
  use Ecto.Migration

  @table :short_url_comments_mapping
  def change do
    create(table(@table)) do
      add(:comment_id, references(:comments))
      add(:short_url_id, references(:short_urls))

      timestamps()
    end

    # A comment belongs to at most one post.
    # A post can have many comments (so it's not unique_index)
    create(unique_index(@table, [:comment_id]))
    create(index(@table, [:short_url_id]))
  end
end
