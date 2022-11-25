defmodule SanbaseWeb.ExAdmin.Project.ContractAddress do
  use ExAdmin.Register

  import Ecto.Query

  register_resource Sanbase.Project.ContractAddress do
    controller do
      after_filter(:set_defaults, only: [:new])
    end
  end

  def set_defaults(conn, params, resource, :new) do
    {conn, params, resource |> set_project_default(params)}
  end

  defp set_project_default(%{project_id: nil} = contract_address, params) do
    Map.get(params, :project_id, nil)
    |> case do
      nil -> contract_address
      project_id -> Map.put(contract_address, :project_id, project_id)
    end
  end
end
