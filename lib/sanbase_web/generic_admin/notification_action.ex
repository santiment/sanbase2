defmodule SanbaseWeb.GenericAdmin.NotificationAction do
  def schema_module, do: Sanbase.Notifications.NotificationAction

  def resource() do
    %{
      actions: [:show],
      index_fields: [
        :id,
        :status,
        :action_type,
        :scheduled_at,
        :requires_verification,
        :verified,
        :inserted_at
      ],
      fields_override: %{
        status: %{
          type: :select,
          collection: NotificationStatusEnum.__enum_map__()
        },
        action_type: %{
          type: :select,
          collection: NotificationActionTypeEnum.__enum_map__()
        },
        requires_verification: %{
          type: :boolean
        },
        verified: %{
          type: :boolean
        }
      }
    }
  end

  def has_many(notification_action) do
    notification_action =
      notification_action
      |> Sanbase.Repo.preload([
        :notifications
      ])

    [
      %{
        resource: "notifications",
        resource_name: "Notifications",
        rows:
          if(notification_action.notifications, do: notification_action.notifications, else: []),
        fields: [:id, :status, :step, :channels, :inserted_at],
        funcs: %{
          channels: fn notification ->
            notification.channels
            |> Enum.map(&to_string/1)
            |> Enum.join(", ")
          end
        },
        create_link_kv: []
      }
    ]
  end
end
