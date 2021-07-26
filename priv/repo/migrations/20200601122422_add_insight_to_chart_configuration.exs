defmodule Sanbase.Repo.Migrations.AddInsightToChartConfiguration do
  use Ecto.Migration

  def change do
    alter table(:chart_configurations) do
      add(:post_id, references(:posts))
    end
  end
end
