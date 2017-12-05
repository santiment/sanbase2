defmodule Sanbase.ExAdmin.Model.Project do
  use ExAdmin.Register

  alias Sanbase.Model.Project
  alias Sanbase.Model.Infrastructure

  register_resource Sanbase.Model.Project do

    controller do
      # doc: https://hexdocs.pm/ex_admin/ExAdmin.Register.html#after_filter/2
      after_filter :set_defaults, only: [:new]
    end
  end

  def set_defaults(conn, params, resource, :new) do
    resource = resource
    |> set_project_infrastructure_default()

    {conn, params, resource}
  end

  defp set_project_infrastructure_default(%Project{infrastructure_id: nil}=project) do
    infrastructure = Infrastructure.get("ETH")

    case infrastructure do
      %Infrastructure{id: id} -> Map.put(project, :infrastructure_id, id)
      _ -> project
    end
  end

  defp set_project_infrastructure_default(%Project{}=project), do: project
end
