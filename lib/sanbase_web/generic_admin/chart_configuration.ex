defmodule SanbaseWeb.GenericAdmin.ChartConfiguration do
  @behaviour SanbaseWeb.GenericAdmin
  def schema_module, do: Sanbase.Chart.Configuration
  def resource_name, do: "chart_configurations"
  def singular_resource_name, do: "chart_configuration"

  def resource do
    %{
      actions: [:new, :edit],
      preloads: [:user, :project],
      index_fields: [:id, :title, :is_public, :user_id],
      new_fields: [:user, :project, :title, :is_public],
      edit_fields: [:title, :is_public],
      belongs_to_fields: %{
        user: SanbaseWeb.GenericAdmin.belongs_to_user(),
        project: SanbaseWeb.GenericAdmin.belongs_to_project()
      },
      fields_override: %{
        user_id: %{
          value_modifier: &SanbaseWeb.GenericAdmin.User.user_link/1
        },
        project_id: %{
          value_modifier: &SanbaseWeb.GenericAdmin.Project.project_link/1
        }
      }
    }
  end
end
