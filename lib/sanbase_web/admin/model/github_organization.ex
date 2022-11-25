defmodule SanbaseWeb.ExAdmin.Project.GithubOrganization do
  use ExAdmin.Register

  register_resource Sanbase.Project.GithubOrganization do
    form org do
      inputs do
        input(
          org,
          :project,
          collection:
            from(p in Sanbase.Project, order_by: p.name)
            |> Sanbase.Repo.all()
        )

        input(org, :organization)
      end
    end

    controller do
      after_filter(:set_defaults, only: [:new])
    end
  end

  def set_defaults(conn, params, resource, :new) do
    resource =
      resource
      |> set_project_default(params)

    {conn, params, resource}
  end

  defp set_project_default(resource, params) do
    Map.get(params, :project_id, nil)
    |> case do
      nil -> resource
      project_id -> Map.put(resource, :project_id, project_id)
    end
  end
end
