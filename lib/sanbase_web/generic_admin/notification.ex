defmodule SanbaseWeb.GenericAdmin.Notification do
  import Ecto.Query
  def schema_module, do: Sanbase.Notifications.Notification

  def resource() do
    %{
      actions: [:show],
      index_fields: [
        :id,
        :status,
        :step,
        :channels,
        :scheduled_at,
        :sent_at,
        :content,
        :display_in_ui,
        :notification_action_id,
        :inserted_at,
        :updated_at
      ],
      fields_override: %{
        status: %{
          type: :select,
          collection: NotificationStatusEnum.__enum_map__()
        },
        step: %{
          type: :select,
          collection: NotificationStepEnum.__enum_map__()
        },
        channels: %{
          type: :multiple_select,
          collection: NotificationChannelEnum.__enum_map__(),
          value_modifier: fn notification ->
            notification.channels
            |> Enum.map(&to_string/1)
            |> Enum.join(", ")
          end
        },
        display_in_ui: %{
          type: :boolean
        },
        template_params: %{
          type: :map
        },
        content: %{
          type: :textarea
        }
      },
      belongs_to_fields: %{
        notification_action: %{
          query: from(na in Sanbase.Notifications.NotificationAction, order_by: na.id),
          resource: "notification_actions",
          search_fields: [:id]
        }
      },
      search_fields: [:id, :content, :status],
      filters: [:status, :step, :display_in_ui, :notification_action_id]
    }
  end

  def has_many(notification) do
    notification =
      notification
      |> Sanbase.Repo.preload([:email_notification])

    [
      %{
        resource: "email_notifications",
        resource_name: "Email Notifications",
        rows: [notification.email_notification],
        fields: [:id, :status, :subject, :body, :inserted_at],
        funcs: %{},
        create_link_kv: []
      }
    ]
  end
end
