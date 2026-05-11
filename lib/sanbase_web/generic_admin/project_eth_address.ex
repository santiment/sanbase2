defmodule SanbaseWeb.GenericAdmin.ProjectEthAddress do
  @behaviour SanbaseWeb.GenericAdmin
  def schema_module, do: Sanbase.ProjectEthAddress
  def resource_name, do: "project_eth_addresses"
  def singular_resource_name, do: "project_eth_address"

  def resource() do
    %{
      actions: [:new, :edit],
      preloads: [:project],
      new_fields: [:project, :address],
      edit_fields: [:project, :address],
      belongs_to_fields: %{
        project: SanbaseWeb.GenericAdmin.belongs_to_project()
      },
      fields_override: %{
        project_id: %{
          value_modifier: &SanbaseWeb.GenericAdmin.Project.project_link/1
        }
      }
    }
  end
end
