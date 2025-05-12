defmodule Sanbase.Workers.SendDeprecationEmailWorker do
  use Oban.Worker, queue: :notifications_queue, max_attempts: 5

  alias Sanbase.Notifications
  alias Sanbase.Notifications.ScheduledDeprecationNotification
  alias Sanbase.Email.MailjetApi
  alias Sanbase.Repo

  require Logger

  @impl Oban.Worker
  def perform(
        %Oban.Job{
          attempt: attempt,
          max_attempts: max_attempts,
          args: %{"notification_id" => notification_id, "email_type" => email_type}
        } = job
      ) do
    Logger.info(
      "Processing deprecation email job for notification_id: #{notification_id}, email_type: #{email_type}, attempt: #{attempt}"
    )

    notification = Notifications.get_scheduled_deprecation(notification_id)

    case process_email(notification, email_type, job) do
      :ok ->
        update_notification_after_successful_send(notification, email_type)
        :ok

      {:error, reason} ->
        if attempt == max_attempts do
          update_notification_dispatch_status(notification, email_type, "error")
        end

        {:error, reason}
    end
  end

  defp process_email(notification, email_type, job) do
    {subject, html_content, title} = content_for_email(notification, email_type)
    campaign_opts = [title: title, subject: subject]

    mailjet_list_key =
      Notifications.get_mailjet_list_key_for_contact_list(notification.contact_list_name)

    case MailjetApi.send_campaign(mailjet_list_key, html_content, campaign_opts) do
      :ok ->
        :ok

      {:error, mailjet_error_reason} ->
        error_message =
          "Failed to send #{email_type} email via Mailjet. Reason: #{inspect(mailjet_error_reason)}"

        Logger.error(
          "#{error_message} for notification #{notification.id}, attempt: #{job.attempt}"
        )

        {:error, error_message}
    end
  end

  defp content_for_email(notification, email_type) do
    base_title = "API Deprecation Notification"

    case email_type do
      "schedule" ->
        {notification.schedule_email_subject, notification.schedule_email_html,
         "#{base_title} - Scheduled"}

      "reminder" ->
        {notification.reminder_email_subject, notification.reminder_email_html,
         "#{base_title} - Reminder"}

      "executed" ->
        {notification.executed_email_subject, notification.executed_email_html,
         "#{base_title} - Executed"}
    end
  end

  defp update_notification_after_successful_send(notification, email_type) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    attrs_to_update =
      case email_type do
        "schedule" ->
          %{schedule_email_sent_at: now, schedule_email_dispatch_status: "sent"}

        "reminder" ->
          %{reminder_email_sent_at: now, reminder_email_dispatch_status: "sent"}

        "executed" ->
          %{
            executed_email_sent_at: now,
            executed_email_dispatch_status: "sent",
            status: "completed"
          }
      end

    # update_db returns :ok or {:error, _}, which is fine for the worker's return if this is the last call
    update_db(notification, attrs_to_update, "after successful send for #{email_type}")
  end

  defp update_notification_dispatch_status(notification, email_type, dispatch_status) do
    attrs_to_update =
      case email_type do
        "schedule" -> %{schedule_email_dispatch_status: dispatch_status}
        "reminder" -> %{reminder_email_dispatch_status: dispatch_status}
        "executed" -> %{executed_email_dispatch_status: dispatch_status}
      end

    update_db(
      notification,
      attrs_to_update,
      "to set #{email_type} dispatch status to '#{dispatch_status}'"
    )
  end

  defp update_db(notification, attrs, context_msg) do
    case ScheduledDeprecationNotification.changeset(notification, attrs) |> Repo.update() do
      {:ok, _updated_notification} ->
        Logger.info("Successfully updated notification #{notification.id} #{context_msg}.")
        :ok

      {:error, changeset} ->
        Logger.error(
          "Failed to update notification #{notification.id} #{context_msg}. Changeset: #{inspect(changeset)}"
        )

        {:error, changeset}
    end
  end
end
