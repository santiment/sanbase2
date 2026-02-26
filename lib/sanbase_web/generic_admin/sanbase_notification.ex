defmodule SanbaseWeb.GenericAdmin.SanbaseNotification do
  def schema_module, do: Sanbase.AppNotifications.Notification

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
      ]
    }
  end
end
