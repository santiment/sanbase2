defmodule Sanbase.Repo.Migrations.FillSourceSlugMappingsTable do
  @moduledoc false
  use Ecto.Migration

  alias Sanbase.Project

  def up do
    setup()

    projects = Project.List.projects()

    insert_data =
      Enum.map(projects, fn %{slug: slug, id: project_id} ->
        %{source: "coinmarketcap", slug: slug, project_id: project_id}
      end)

    Sanbase.Repo.insert_all(Project.SourceSlugMapping, insert_data, on_conflict: :nothing)
  end

  def down do
    :ok
  end

  defp setup do
    Application.ensure_all_started(:tzdata)
  end
end
