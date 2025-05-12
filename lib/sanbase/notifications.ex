defmodule Sanbase.Notifications do
  @moduledoc """
  The Notifications context.
  """

  require Logger

  import Ecto.Query, warn: false
  alias Sanbase.Repo

  alias Sanbase.Notifications.NotificationTemplate
  alias Sanbase.Notifications.ScheduledDeprecationNotification
  alias Sanbase.Workers.SendDeprecationEmailWorker
  alias Oban

  @contact_list_to_mailjet_key %{
    "API Users Only" => :metric_updates_dev,
    "API & Sanbase Users - Metric Updates" => :metric_updates_dev
  }

  @doc """
  Returns the list of notification_templates.

  ## Examples

      iex> list_notification_templates()
      [%NotificationTemplate{}, ...]

  """
  def list_notification_templates do
    Repo.all(NotificationTemplate)
  end

  @doc """
  Gets a single notification_template.

  Raises `Ecto.NoResultsError` if the Notification template does not exist.

  ## Examples

      iex> get_notification_template!(123)
      %NotificationTemplate{}

      iex> get_notification_template!(456)
      ** (Ecto.NoResultsError)

  """
  def get_notification_template!(id), do: Repo.get!(NotificationTemplate, id)

  @doc """
  Creates a notification_template.

  ## Examples

      iex> create_notification_template(%{field: value})
      {:ok, %NotificationTemplate{}}

      iex> create_notification_template(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_notification_template(attrs \\ %{}) do
    %NotificationTemplate{}
    |> NotificationTemplate.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a notification_template.

  ## Examples

      iex> update_notification_template(notification_template, %{field: new_value})
      {:ok, %NotificationTemplate{}}

      iex> update_notification_template(notification_template, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_notification_template(%NotificationTemplate{} = notification_template, attrs) do
    notification_template
    |> NotificationTemplate.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a notification_template.

  ## Examples

      iex> delete_notification_template(notification_template)
      {:ok, %NotificationTemplate{}}

      iex> delete_notification_template(notification_template)
      {:error, %Ecto.Changeset{}}

  """
  def delete_notification_template(%NotificationTemplate{} = notification_template) do
    Repo.delete(notification_template)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking notification_template changes.

  ## Examples

      iex> change_notification_template(notification_template)
      %Ecto.Changeset{data: %NotificationTemplate{}}

  """
  def change_notification_template(%NotificationTemplate{} = notification_template, attrs \\ %{}) do
    NotificationTemplate.changeset(notification_template, attrs)
  end

  @doc """
  Gets a template for specific action, step, and channel.
  If no channel-specific template is found, falls back to "all" channel template.
  """
  def get_template(action, step, channel \\ "all", mime_type \\ "text/plain") do
    query =
      from(nt in NotificationTemplate,
        where:
          nt.action == ^action and
            nt.step == ^step and
            nt.channel == ^channel and
            nt.mime_type == ^mime_type,
        limit: 1
      )

    case Repo.one(query) do
      nil ->
        # Try again with "all" channel
        fallback_query =
          from(nt in NotificationTemplate,
            where:
              nt.action == ^action and
                nt.step == ^step and
                nt.channel == "all" and
                nt.mime_type == ^mime_type,
            limit: 1
          )

        Repo.one(fallback_query)

      template ->
        template
    end
  end

  @doc """
  Creates a scheduled API endpoint deprecation notification and schedules associated email jobs.

  The `attrs` are expected to come from the `ScheduledDeprecationLive` form and include:
  - `deprecation_date` (string in "YYYY-MM-DD" format)
  - `contact_list_name` (string, e.g., "API Users Only")
  - `api_endpoint` (string)
  - `links` (list of strings)
  - `schedule_email_subject` (string)
  - `schedule_email_html` (string)
  - `reminder_email_subject` (string)
  - `reminder_email_html` (string)
  - `executed_email_subject` (string)
  - `executed_email_html` (string)

  Three emails are scheduled:
  1. Initial "schedule" email: 1 hour after this function is called.
  2. "Reminder" email: 3 days before the `deprecation_date` at 12:00 PM UTC.
  3. "Executed" email: On the `deprecation_date` at 12:00 PM UTC.
  """
  def create_scheduled_deprecation(attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:prepare_data, fn _repo, _changes ->
      prepare_deprecation_data(attrs)
    end)
    |> Ecto.Multi.insert(:notification, fn %{prepare_data: data_for_changeset} ->
      ScheduledDeprecationNotification.changeset(
        %ScheduledDeprecationNotification{},
        data_for_changeset
      )
    end)
    |> Ecto.Multi.run(:schedule_jobs, fn _repo, %{notification: notification} ->
      schedule_deprecation_email_jobs(notification)
    end)
    |> Ecto.Multi.update(:update_notification_with_job_ids, fn %{
                                                                 schedule_jobs: job_ids,
                                                                 notification: notification
                                                               } ->
      ScheduledDeprecationNotification.changeset(notification, job_ids)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{update_notification_with_job_ids: notification}} ->
        {:ok, notification}

      {:error, :prepare_data, error_reason, _changes} ->
        {:error, error_reason}

      {:error, _step, error_value, _changes} ->
        {:error, error_value}
    end
  end

  defp prepare_deprecation_data(attrs) do
    with {:ok, deprecation_date} <- Date.from_iso8601(attrs.deprecation_date),
         mailjet_list_key <- Map.get(@contact_list_to_mailjet_key, attrs.contact_list_name) do
      now = DateTime.utc_now()

      # 1. Initial email: 1 hour from now
      schedule_email_scheduled_at = DateTime.add(now, 1, :hour) |> DateTime.truncate(:second)

      # 2. Reminder email: 3 days before deprecation_date at 12:00 PM UTC
      reminder_date = Date.add(deprecation_date, -3)

      reminder_email_scheduled_at =
        DateTime.new!(reminder_date, ~T[12:00:00], "Etc/UTC")

      # 3. Executed email: on deprecation_date at 12:00 PM UTC
      executed_email_scheduled_at =
        DateTime.new!(deprecation_date, ~T[12:00:00], "Etc/UTC")

      data_for_changeset = %{
        deprecation_date: deprecation_date,
        contact_list_name: attrs.contact_list_name,
        mailjet_list_key: mailjet_list_key,
        api_endpoint: attrs.api_endpoint,
        links: attrs.links,
        schedule_email_subject: attrs.schedule_email_subject,
        schedule_email_html: attrs.schedule_email_html,
        schedule_email_scheduled_at: schedule_email_scheduled_at,
        reminder_email_subject: attrs.reminder_email_subject,
        reminder_email_html: attrs.reminder_email_html,
        reminder_email_scheduled_at: reminder_email_scheduled_at,
        executed_email_subject: attrs.executed_email_subject,
        executed_email_html: attrs.executed_email_html,
        executed_email_scheduled_at: executed_email_scheduled_at,
        # Set to active as jobs are being scheduled
        status: "active"
      }

      {:ok, data_for_changeset}
    else
      :error -> {:error, {:invalid_date, attrs.deprecation_date}}
      nil -> {:error, {:unknown_contact_list, attrs.contact_list_name}}
    end
  end

  defp schedule_deprecation_email_jobs(notification) do
    args_schedule = %{notification_id: notification.id, email_type: "schedule"}
    args_reminder = %{notification_id: notification.id, email_type: "reminder"}
    args_executed = %{notification_id: notification.id, email_type: "executed"}

    multi =
      Ecto.Multi.new()
      |> Ecto.Multi.run(:schedule_job, fn _repo, _changes ->
        job =
          SendDeprecationEmailWorker.new(args_schedule,
            scheduled_at: notification.schedule_email_scheduled_at
          )

        case Oban.insert(Sanbase.Notifications.EmailNotifier.oban_conf_name(), job) do
          {:ok, job} -> {:ok, job.id}
          {:error, reason} -> {:error, {:oban_insert_failed, :schedule, reason}}
        end
      end)
      |> Ecto.Multi.run(:reminder_job, fn _repo, _changes ->
        job =
          SendDeprecationEmailWorker.new(args_reminder,
            scheduled_at: notification.reminder_email_scheduled_at
          )

        case Oban.insert(Sanbase.Notifications.EmailNotifier.oban_conf_name(), job) do
          {:ok, job} -> {:ok, job.id}
          {:error, reason} -> {:error, {:oban_insert_failed, :reminder, reason}}
        end
      end)
      |> Ecto.Multi.run(:executed_job, fn _repo, _changes ->
        job =
          SendDeprecationEmailWorker.new(args_executed,
            scheduled_at: notification.executed_email_scheduled_at
          )

        case Oban.insert(Sanbase.Notifications.EmailNotifier.oban_conf_name(), job) do
          {:ok, job} -> {:ok, job.id}
          {:error, reason} -> {:error, {:oban_insert_failed, :executed, reason}}
        end
      end)

    case Repo.transaction(multi) do
      {:ok, results} ->
        job_ids = %{
          schedule_email_job_id: Integer.to_string(results.schedule_job),
          reminder_email_job_id: Integer.to_string(results.reminder_job),
          executed_email_job_id: Integer.to_string(results.executed_job)
        }

        {:ok, job_ids}

      {:error, step, reason, _changes} ->
        Logger.error("Failed to schedule Oban jobs during step #{step}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Returns the Mailjet list key (atom) for a given contact list name.
  Returns `nil` if the contact list name is not found in the mapping.
  """
  def get_mailjet_list_key_for_contact_list(contact_list_name) do
    @contact_list_to_mailjet_key[contact_list_name]
  end

  @doc """
  Retrieves a scheduled deprecation notification by its ID.
  """
  def get_scheduled_deprecation(id) do
    Repo.get(ScheduledDeprecationNotification, id)
  end

  @doc """
  Lists all scheduled deprecation notifications, most recent first.
  TODO: Add filtering and pagination options.
  """
  def list_scheduled_deprecations(_opts \\ []) do
    ScheduledDeprecationNotification
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  end
end
