defmodule SanbaseWeb.GenericAdmin.SanbaseNotification do
  @behaviour SanbaseWeb.GenericAdmin
  def schema_module, do: Sanbase.AppNotifications.Notification

  def resource_name, do: "sanbase_notifications"
  def singular_resource_name, do: "sanbase_notification"

  def resource() do
    %{
      index_fields: [
        :id,
        :type,
        :title,
        :content,
        :entity_type,
        :entity_name,
        :entity_id,
        :user_id,
        :is_system_generated,
        :is_broadcast,
        :grouping_key,
        :is_deleted,
        :inserted_at
      ],
      custom_index_actions: [
        %{
          name: "Broadcast Overview",
          path: "/admin/notifications/broadcast/overview"
        },
        %{
          name: "New Broadcast",
          path: "/admin/notifications/broadcast"
        }
      ]
    }
  end
end
