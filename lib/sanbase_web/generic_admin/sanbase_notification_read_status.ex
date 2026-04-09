defmodule SanbaseWeb.GenericAdmin.SanbaseNotificationReadStatus do
  def schema_module, do: Sanbase.AppNotifications.NotificationReadStatus

  def resource_name, do: "sanbase_notification_read_statuses"
  def singular_resource_name, do: "sanbase_notification_read_status"

  def resource() do
    %{
      index_fields: [
        :id,
        :user_id,
        :notification_id,
        :read_at,
        :inserted_at,
        :updated_at
      ],
      custom_index_actions: [
        %{
          name: "Broadcast Overview",
          path: "/admin/notifications/broadcast/overview"
        }
      ]
    }
  end
end
