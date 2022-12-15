defmodule Sanbase.Project.Job do
  def compute_ecosystem_full_path() do
    projects = Sanbase.Project.List.projects(include_hidden: true)
    slug_to_project_map = Map.new(projects, &{&1.slug, &1})

    Enum.map(projects, fn project ->
      {project, get_ecosystem_full_path(project, slug_to_project_map)}
    end)
    |> Enum.map(fn
      {project, []} -> {project, ""}
      {project, path} -> {project, "/" <> Enum.join(path, "/") <> "/"}
    end)
  end

  defp get_ecosystem_full_path(project, slug_to_project_map) do
    case project.ecosystem == project.slug do
      true ->
        [project.slug]

      false ->
        parent_ecosystem_project = Map.get(slug_to_project_map, project.ecosystem)
        get_ecosystem_full_path(parent_ecosystem_project, slug_to_project_map) ++ [project.slug]
    end
  end
end
