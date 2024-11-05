defmodule Sanbase.Notifications.EmailNotification do
  use Ecto.Schema
  import Ecto.Changeset

  schema "email_notifications" do
    field(:to_addresses, {:array, :string})
    field(:subject, :string)
    field(:content, :string)
    field(:status, :string, default: "pending")
    field(:approved_at, :utc_datetime)
    field(:sent_at, :utc_datetime)

    belongs_to(:notification, Sanbase.Notifications.Notification)

    timestamps()
  end

  @doc false
  def changeset(email_notification, attrs) do
    email_notification
    |> cast(attrs, [
      :to_addresses,
      :subject,
      :content,
      :status,
      :approved_at,
      :sent_at,
      :notification_id
    ])
    |> validate_required([:to_addresses, :subject, :content])
    |> validate_inclusion(:status, ["pending", "approved", "rejected"])
    |> validate_emails()
  end

  defp validate_emails(changeset) do
    case get_change(changeset, :to_addresses) do
      nil ->
        changeset

      addresses ->
        if Enum.all?(addresses, &valid_email?/1) do
          changeset
        else
          add_error(changeset, :to_addresses, "contains invalid email addresses")
        end
    end
  end

  defp valid_email?(email) do
    # Basic email validation - you might want to use a more sophisticated regex
    email =~ ~r/^[^\s]+@[^\s]+\.[^\s]+$/
  end
end
