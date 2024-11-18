defmodule SanbaseWeb.GenericAdmin.Notification do
  def schema_module, do: Sanbase.Notifications.Notification

  def resource() do
    %{
      actions: [:new],
      new_fields: [:action, :params, :channels, :step],
      index_fields: [
        :id,
        :action,
        :step,
        :params,
        :channels,
        :processed_for_discord,
        :processed_for_email
      ],
      fields_override: %{
        params: %{
          value_modifier: fn ntf ->
            Jason.encode!(ntf.params)
          end
        },
        action: %{
          collection: Sanbase.Notifications.Notification.supported_actions(),
          type: :select
        },
        step: %{
          collection: Sanbase.Notifications.Notification.supported_steps(),
          type: :select
        },
        channels: %{
          collection: Sanbase.Notifications.Notification.supported_channels(),
          type: :multiselect,
          value_modifier: &format_channels/1
        }
      }
    }
  end

  defp format_params(%{params: params}) do
    Jason.encode!(params)
  end

  defp format_channels(%{channels: channels}) do
    Jason.encode!(channels)
  end

  def after_filter(notification, _params) do
    Sanbase.Notifications.Handler.handle_notification(notification)
  end
end
