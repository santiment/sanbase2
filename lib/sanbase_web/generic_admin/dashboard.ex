defmodule SanbaseWeb.GenericAdmin.Dashboard do
  def schema_module, do: Sanbase.Dashboards.Dashboard
  def resource_name, do: "dashboards"

  def resource do
    %{
      actions: [:show, :edit],
      preloads: [:user],
      index_fields: [:id, :name, :is_public, :user_id],
      fields_override: %{
        user_id: %{
          value_modifier: &SanbaseWeb.GenericAdmin.User.user_link/1
        }
      }
    }
  end
end
