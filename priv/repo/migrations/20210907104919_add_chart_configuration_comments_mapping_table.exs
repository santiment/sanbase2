defmodule Sanbase.Repo.Migrations.AddChartConfigurationCommentsMappingTable do
  use Ecto.Migration

  @table :chart_configuration_comments_mapping
  def change do
    create(table(@table)) do
      add(:comment_id, references(:comments, on_delete: :delete_all))
      add(:chart_configuration_id, references(:chart_configurations, on_delete: :delete_all))

      timestamps()
    end

    # A comment belongs to at most one post.
    # A post can have many comments (so it's not unique_index)
    create(unique_index(@table, [:comment_id]))
    create(index(@table, [:chart_configuration_id]))
  end
end
