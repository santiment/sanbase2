defmodule Sanbase.Repo.Migrations.AddGranularityToTopicBatches do
  use Ecto.Migration

  def change do
    alter table(:topic_batches) do
      add(:granularity, :string, null: false, default: "week")
    end

    create(index(:topic_batches, [:granularity, :state, :interval_start]))
  end
end
