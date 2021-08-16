defmodule Sanbase.Repo.Migrations.AddFinishedObanJobsTable do
  use Ecto.Migration

  def change do
    create table(:finished_oban_jobs) do
      add(:queue, :string)
      add(:worker, :string)
      add(:args, :map)
      add(:original_id, :integer)
      add(:original_inserted_at, :naive_datetime)
      add(:original_completed_at, :naive_datetime)

      timestamps()
    end

    create_if_not_exists(index(:finished_oban_jobs, [:queue]))
    create_if_not_exists(index(:finished_oban_jobs, [:original_inserted_at]))
    create_if_not_exists(index(:finished_oban_jobs, [:args], using: :gin, prefix: prefix))
  end
end
