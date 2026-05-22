defmodule Sanbase.Repo.Migrations.RemoveGranularityFromTopicBatches do
  use Ecto.Migration

  def change do
    drop(index(:topic_batches, [:granularity, :state, :interval_start]))

    alter table(:topic_batches) do
      remove(:granularity, :string)
    end

    create(index(:topic_batches, [:state, :interval_start]))
  end
end
