defmodule Sanbase.Project.Job do
  @doc ~s"""
  Projects have two fields for ecosystem: `ecosystem` and `ecosystem_full_path`.
  `ecosystem` holds just the ecosystem name, while `ecosystem_full_path` is the
  path enumeration, going to the root. For example if X is built on top of Arbitrum,
  and Arbitrum is built on top of Ethereum, then we'll have the following:
    ecosystem of Arbitrum: Ethereum
    ecosystem_full_path of Arbitrum: /ethereum/
    ecosystem of X: Arbitrum
    ecosystem_full_path of X: /ethereum/arbitrum

  This function uses the ecosystem to compute the ecosystem_full_path (recurisvelly,
  where needed).
  """
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
