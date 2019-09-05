defmodule Sanbase.Repo.Migrations.AddProjectMarketSegmentsTable do
  use Ecto.Migration
  @table "project_market_segments"
  def change do
    create table(@table) do
      add(:project_id, references(:project))
      add(:market_segment_id, references(:market_segments))

      timestamps()
    end

    create(unique_index(:project_market_segments, [:project_id, :market_segment_id]))
  end
end
