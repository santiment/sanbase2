defmodule Sanbase.ExAdmin.Model.Project.GithubOrganization do
  use ExAdmin.Register

  register_resource Sanbase.Model.Project.GithubOrganization do
    form org do
      inputs do
        input(org, :organization)

        input(
          org,
          :project,
          collection:
            from(p in Sanbase.Model.Project, order_by: p.name)
            |> Sanbase.Repo.all()
        )
      end
    end
  end
end
