defmodule SanbaseWeb.GenericAdmin.EmailNotification do
  import Ecto.Query
  def schema_module, do: Sanbase.Notifications.EmailNotification

  def resource() do
    %{
      actions: [:show],
      preloads: [:notification],
      index_fields: [
        :id,
        :subject,
        :status,
        :approved_at,
        :sent_at,
        :inserted_at
      ],
      fields_override: %{
        content: %{
          type: :text
        },
        to_addresses: %{
          type: :list
        },
        status: %{
          collection: ["pending", "approved", "rejected"],
          type: :select
        }
      },
      belongs_to_fields: %{
        notification: %{
          query: from(n in Sanbase.Notifications.Notification, order_by: n.id),
          transform: fn rows -> Enum.map(rows, &{&1.id, &1.id}) end,
          resource: "notifications",
          search_fields: [:id]
        }
      },
      custom_actions: [
        %{
          # This action appears on show page
          type: :show,
          # Action identifier, we need same name function defined in this module
          name: "send_email",
          # Button label
          label: "Send Email",
          # CSS class
          class: "button",
          # Optional confirmation
          confirm: "Are you sure you want to send this email?"
        }
      ]
    }
  end

  def send_email(email_notification) do
    dbg(email_notification)
    # update approved_at to now
    # send email
    # update sent_at to now and status to "sent"
    # return ok
    {:ok, "Email sent successfully"}
  end
end
