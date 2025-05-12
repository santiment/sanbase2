defmodule Sanbase.Notifications.ScheduledDeprecationNotification do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}
  schema "scheduled_deprecation_notifications" do
    field(:deprecation_date, :date)
    field(:contact_list_name, :string)
    # field :mailjet_list_key, :atom # Field removed as per user request
    field(:api_endpoint, :string)
    field(:links, {:array, :string})

    # Initial Schedule Email
    field(:schedule_email_subject, :string)
    field(:schedule_email_html, :string)
    field(:schedule_email_scheduled_at, :utc_datetime)
    field(:schedule_email_job_id, :string)
    field(:schedule_email_sent_at, :utc_datetime)
    field(:schedule_email_dispatch_status, :string, default: "pending")

    # Reminder Email
    field(:reminder_email_subject, :string)
    field(:reminder_email_html, :string)
    field(:reminder_email_scheduled_at, :utc_datetime)
    field(:reminder_email_job_id, :string)
    field(:reminder_email_sent_at, :utc_datetime)
    field(:reminder_email_dispatch_status, :string, default: "pending")

    # Executed Email (on deprecation day)
    field(:executed_email_subject, :string)
    field(:executed_email_html, :string)
    field(:executed_email_scheduled_at, :utc_datetime)
    field(:executed_email_job_id, :string)
    field(:executed_email_sent_at, :utc_datetime)
    field(:executed_email_dispatch_status, :string, default: "pending")

    field(:status, :string, default: "pending")

    timestamps()
  end

  @doc false
  def changeset(notification, attrs) do
    notification
    |> cast(attrs, [
      :deprecation_date,
      :contact_list_name,
      # :mailjet_list_key, # Removed from cast
      :api_endpoint,
      :links,
      :schedule_email_subject,
      :schedule_email_html,
      :schedule_email_scheduled_at,
      :schedule_email_job_id,
      :schedule_email_sent_at,
      :schedule_email_dispatch_status,
      :reminder_email_subject,
      :reminder_email_html,
      :reminder_email_scheduled_at,
      :reminder_email_job_id,
      :reminder_email_sent_at,
      :reminder_email_dispatch_status,
      :executed_email_subject,
      :executed_email_html,
      :executed_email_scheduled_at,
      :executed_email_job_id,
      :executed_email_sent_at,
      :executed_email_dispatch_status,
      :status
    ])
    |> validate_required([
      :deprecation_date,
      :contact_list_name,
      # :mailjet_list_key, # Removed from validation
      :api_endpoint,
      :links,
      :schedule_email_subject,
      :schedule_email_html,
      :schedule_email_scheduled_at,
      :reminder_email_subject,
      :reminder_email_html,
      :reminder_email_scheduled_at,
      :executed_email_subject,
      :executed_email_html,
      :executed_email_scheduled_at,
      :status
    ])
    |> validate_inclusion(:status, ["pending", "active", "completed", "failed", "cancelled"])
    |> validate_inclusion(:schedule_email_dispatch_status, ["pending", "sent", "error"],
      allow_nil: true
    )
    |> validate_inclusion(:reminder_email_dispatch_status, ["pending", "sent", "error"],
      allow_nil: true
    )
    |> validate_inclusion(:executed_email_dispatch_status, ["pending", "sent", "error"],
      allow_nil: true
    )

    # Add more validations as needed, e.g., for URL formats in links,
    # date constraints for deprecation_date vs send_at dates.
  end
end
