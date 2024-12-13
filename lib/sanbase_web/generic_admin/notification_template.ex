defmodule SanbaseWeb.GenericAdmin.NotificationTemplate do
  alias Sanbase.Notifications.Notification
  def schema_module, do: Sanbase.Notifications.NotificationTemplate

  def resource() do
    %{
      fields_override: %{
        required_params: %{
          value_modifier: fn template ->
            Jason.encode!(template.required_params)
          end
        },
        template: %{
          type: :text
        },
        channel: %{
          type: :select,
          collection: Notification.supported_channels() ++ ["all"]
        },
        action: %{
          type: :select,
          collection: Notification.supported_actions()
        },
        step: %{
          type: :select,
          collection: Notification.supported_steps()
        }
      }
    }
  end
end
