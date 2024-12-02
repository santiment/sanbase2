defmodule SanbaseWeb.GenericAdmin.Notification do
  def schema_module, do: Sanbase.Notifications.Notification

  def resource() do
    %{
      index_fields: [
        :id,
        :action,
        :step,
        :params,
        :channel,
        :status,
        :is_manual
      ],
      fields_override: %{
        action: %{
          collection: Sanbase.Notifications.Notification.supported_actions(),
          type: :select
        },
        step: %{
          collection: Sanbase.Notifications.Notification.supported_steps(),
          type: :select
        },
        channel: %{
          collection: Sanbase.Notifications.Notification.supported_channels(),
          type: :select
        },
        params: %{
          value_modifier: fn ntf ->
            Jason.encode!(ntf.params)
          end
        }
      }
    }
  end

  def after_filter(notification, _params) do
    Sanbase.Notifications.Handler.handle_notification(notification)
  end
end
