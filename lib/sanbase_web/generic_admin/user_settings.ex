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
            us.settings
            |> normalize_settings()
            |> Map.drop([:alerts_fired, "alerts_fired"])
            |> Jason.encode!(pretty: true)
          end
        }
      }
    }
  end

  defp normalize_settings(nil), do: %{}
  defp normalize_settings(settings) when is_struct(settings), do: Map.from_struct(settings)
  defp normalize_settings(settings) when is_map(settings), do: settings
end
