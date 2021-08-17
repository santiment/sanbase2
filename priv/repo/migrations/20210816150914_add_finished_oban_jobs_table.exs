defmodule Sanbase.Repo.Migrations.AddFinishedObanJobsTable do
  use Ecto.Migration

  def change do
    create table(:finished_oban_jobs) do
      add(:queue, :string)
      add(:worker, :string)
      add(:args, :map)
      add(:inserted_at, :naive_datetime)
      add(:completed_at, :naive_datetime)
    end

    prefix = get_prefix()
    create_if_not_exists(index(:finished_oban_jobs, [:queue]))
    create_if_not_exists(index(:finished_oban_jobs, [:inserted_at]))
    create_if_not_exists(index(:finished_oban_jobs, [:args], using: :gin, prefix: prefix))
  end

  defp get_prefix() do
    case Config.module_get(Sanbase, :deployment_env) do
      env when env in ["stage", "prod"] -> "sanbase2"
      _ -> "public"
    end
  end
end
