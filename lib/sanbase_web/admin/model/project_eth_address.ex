defmodule Sanbase.ExAdmin.Model.ProjectEthAddress do
  use ExAdmin.Register

  import Ecto.Query, warn: false

  alias Sanbase.Model.ProjectEthAddress
  alias Sanbase.Model.Project

  register_resource Sanbase.Model.ProjectEthAddress do
    form project do
      inputs do
        input(project, :address)

        input(
          project,
          :project,
          collection: from(p in Project, order_by: p.name) |> Sanbase.Repo.all()
        )
      end
    end

    controller do
      # doc: https://hexdocs.pm/ex_admin/ExAdmin.Register.html#after_filter/2
      after_filter(:set_defaults, only: [:new])
    end
  end

  def set_defaults(conn, params, resource, :new) do
    resource =
      resource
      |> set_project_default(params)

    {conn, params, resource}
  end

  defp set_project_default(%ProjectEthAddress{project_id: nil} = address, params) do
    Map.get(params, :project_id, nil)
    |> case do
      nil -> address
      project_id -> Map.put(address, :project_id, project_id)
    end
  end
end
