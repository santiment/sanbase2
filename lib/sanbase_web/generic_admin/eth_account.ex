defmodule SanbaseWeb.GenericAdmin.EthAccount do
  @moduledoc false
  def schema_module, do: Sanbase.Accounts.EthAccount

  def resource do
    %{
      actions: [:new, :edit, :delete],
      index_fields: [:id, :address, :user_id, :inserted_at, :updated_at],
      new_fields: [:address, :user],
      edit_fields: [:address],
      preloads: [:user],
      belongs_to_fields: %{user: %{resource: "users", search_fields: [:id, :username, :email]}},
      fields_override: %{
        user_id: %{
          value_modifier: &SanbaseWeb.GenericAdmin.User.user_link/1
        }
      }
    }
  end
end
