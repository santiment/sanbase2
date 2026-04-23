defmodule SanbaseWeb.GenericAdmin.UserSettings do
  @behaviour SanbaseWeb.GenericAdmin
  @schema_module Sanbase.Accounts.UserSettings
  def schema_module(), do: @schema_module
  def resource_name, do: "user_settings"
  def singular_resource_name, do: "user_settings"

  def resource do
    %{
      index_fields: [:id],
      fields_override: %{
        settings: %{
          value_modifier: fn us ->
            Map.from_struct(us.settings)
            |> Map.delete(:alerts_fired)
            |> Jason.encode!(pretty: true)
          end
        }
      }
    }
  end
end
