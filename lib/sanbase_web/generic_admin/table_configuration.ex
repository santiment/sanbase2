defmodule SanbaseWeb.GenericAdmin.TableConfiguration do
  @behaviour SanbaseWeb.GenericAdmin
  def schema_module, do: Sanbase.TableConfiguration
  def resource_name, do: "table_configurations"
  def singular_resource_name, do: "table_configuration"

  def resource do
    %{
      actions: [:new, :edit],
      preloads: [:user],
      index_fields: [:id, :title, :is_public, :user_id],
      new_fields: [:title, :is_public],
      edit_fields: [:title, :is_public],
      fields_override: %{
        user_id: %{
          value_modifier: &SanbaseWeb.GenericAdmin.User.user_link/1
        }
      }
    }
  end
end
