defmodule Sanbase.Repo.Migrations.AddOnDeletePostsMetrics do
  @moduledoc false
  use Ecto.Migration

  @table "posts_metrics"
  def up do
    drop(constraint(@table, "posts_metrics_post_id_fkey"))
    drop(constraint(@table, "posts_metrics_metric_id_fkey"))

    alter table(@table) do
      modify(:post_id, references(:posts, on_delete: :delete_all))
      modify(:metric_id, references(:metrics, on_delete: :delete_all))
    end

    create(unique_index(@table, [:post_id, :metric_id]))
  end

  def down do
    drop(unique_index(@table, [:post_id, :metric_id]))
    drop(constraint(@table, "posts_metrics_post_id_fkey"))
    drop(constraint(@table, "posts_metrics_metric_id_fkey"))

    alter table(@table) do
      modify(:post_id, references(:posts))
      modify(:metric_id, references(:metrics))
    end
  end
end
