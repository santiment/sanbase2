defmodule SanbaseWeb.GenericAdmin.NotificationTemplate do
  alias Sanbase.Notifications.Notification
  def schema_module, do: Sanbase.Notifications.NotificationTemplate

  def resource() do
    %{
      actions: [:new, :edit],
      new_fields: [:action, :step, :channel, :mime_type, :required_params, :template],
      edit_fields: [:action, :step, :channel, :mime_type, :required_params, :template],
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
        },
        mime_type: %{
          type: :select,
          collection: Notification.supported_mime_types()
        }
      }
    }
  end
end
