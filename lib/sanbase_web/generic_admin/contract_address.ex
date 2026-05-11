defmodule SanbaseWeb.GenericAdmin.ContractAddress do
  @behaviour SanbaseWeb.GenericAdmin
  def schema_module, do: Sanbase.Project.ContractAddress
  def resource_name, do: "contract_addresses"
  def singular_resource_name, do: "contract_address"

  def resource() do
    %{
      actions: [:new, :edit, :delete],
      preloads: [:project],
      new_fields: [:project, :address, :decimals, :label, :description],
      edit_fields: [:project, :address, :decimals, :label, :description],
      belongs_to_fields: %{
        project: SanbaseWeb.GenericAdmin.belongs_to_project()
      },
      fields_override: %{
        description: %{
          type: :text
        },
        project_id: %{
          value_modifier: &SanbaseWeb.GenericAdmin.Project.project_link/1
        }
      }
    }
  end
end
