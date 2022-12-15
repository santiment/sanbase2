defmodule Sanbase.Repo.Migrations.AddProjectEcosystemField do
  use Ecto.Migration

  import Ecto.Query

  def change do
    alter table(:project) do
      add(:ecosystem, :string)
      add(:ecosystem_full_path, :string)
    end
  end

  defp fill_ecosystem() do
    projects = projects()

    ticker_to_name_map = Map.new(projects, &{&1.ticker, &1.name})

    projects
    |> Enum.map(fn project ->
      cond do
        String.downcase(project.infrastructure.code) == "own" ->
          {project.slug, project.name}

        String.upcase(project.infrastructure.code) == project.infrastructure.code ->
          {project.slug, Map.get(ticker_to_name_map, project.infrastructure.code)}

        true ->
          {project.slug, project.infrastructure.code}
      end
    end)
  end

  defp projects() do
    Sanbase.Project.Job.compute_ecosystem_full_path()
    |> Enum.reduce(
      Ecto.Multi.new(),
      fn {project, ecosystem_full_path}, multi ->
        changeset =
          project
          |> Sanbase.Project.changeset(%{ecosystem_full_path: ecosystem_full_path})

        Ecto.Multi.update(multi, project.slug, changeset, on_conflict: :nothing)
      end
    )
    |> Sanbase.Repo.transaction()
    |> case do
      {:ok, _result} -> :ok
      {:error, _name, error, _changes_so_far} -> {:error, error}
    end
  end
end
