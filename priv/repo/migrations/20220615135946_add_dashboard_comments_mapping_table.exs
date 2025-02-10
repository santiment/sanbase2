defmodule Sanbase.Repo.Migrations.AddDashboardCommentsMappingTable do
  @moduledoc false
  use Ecto.Migration

  @table :dashboard_comments_mapping
  def change do
    create(table(@table)) do
      add(:comment_id, references(:comments, on_delete: :delete_all))
      add(:dashboard_id, references(:dashboards, on_delete: :delete_all))

      timestamps()
    end

    create(unique_index(@table, [:comment_id]))
    create(index(@table, [:dashboard_id]))
  end
end
