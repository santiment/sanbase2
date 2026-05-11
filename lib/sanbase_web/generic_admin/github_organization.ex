defmodule SanbaseWeb.GenericAdmin.GithubOrganization do
  @behaviour SanbaseWeb.GenericAdmin
  def schema_module, do: Sanbase.Project.GithubOrganization
  def resource_name, do: "github_organizations"
  def singular_resource_name, do: "github_organization"

  def resource() do
    %{
      actions: [:new, :edit, :delete],
      preloads: [:project],
      new_fields: [:project, :organization],
      edit_fields: [:project, :organization],
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
