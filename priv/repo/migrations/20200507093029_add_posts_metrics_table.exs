defmodule Sanbase.Repo.Migrations.AddMetricsTable do
  use Ecto.Migration

  def change do
    create table("posts_metrics") do
      add(:post_id, references(:posts))
      add(:metric_id, references(:metrics))
    end
  end
end
