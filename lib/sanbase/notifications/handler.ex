defmodule Sanbase.Notifications.Handler do
  import Ecto.Query
  import Sanbase.DateTimeUtils, only: [seconds_after: 1]

  alias Sanbase.{Repo, Notifications.Notification}

  # The metric registry events and manual notifications come from admin pod, so we use the admin Oban config
  @oban_conf_name :oban_admin

  @default_channels %{
    "metric_created" => ["discord", "email"],
    "metric_updated" => ["discord", "email"],
    "metric_deleted" => ["discord", "email"],
    "alert" => ["discord"]
  }

  def handle_metric_registry_event(event) do
    event_type = event.data.event_type

    case event_type do
      :create_metric_registry ->
        handle_metric_registry_created_event(event)

      :update_metric_registry ->
        handle_metric_registry_updated_event(event)
    end

    :ok
  end

  def handle_metric_registry_created_event(event) do
    metric = event.data.metric

    if should_notify_metric_event?(event.data.id) do
      handle_notification(%{
        action: "metric_created",
        step: "all",
        params: %{metrics_list: [metric]},
        metric_registry_id: event.data.id
      })
    end
  end

  def handle_metric_registry_updated_event(event) do
    metric_registry_id = event.data.id
    last_version = fetch_last_version(Sanbase.Metric.Registry, metric_registry_id)

    case last_version.patch do
      # if deprecation was undone, cancel all scheduled notifications
      %{is_deprecated: {:changed, {:primitive_change, true, false}}} ->
        cancel_scheduled_notifications(metric_registry_id)

      %{hard_deprecate_after: {:changed, {:primitive_change, _old, new_date}}} ->
        base_notification = %{
          action: "metric_deleted",
          params: %{
            metrics_list: [event.data.metric],
            scheduled_at: new_date
          },
          metric_registry_id: metric_registry_id
        }

        handle_metric_deleted_notification(base_notification)

      _ ->
        :ok
    end
  end

  def handle_metric_deleted_notification(base_notification) do
    # Immediate notification for "before" step
    response = handle_notification(Map.put(base_notification, :step, "before"))

    scheduled_at = base_notification.params.scheduled_at

    # Get all reminder dates from the scheduler
    reminder_dates =
      Sanbase.Notifications.ReminderScheduler.calculate_reminder_dates(scheduled_at)

    # Schedule reminder notifications for each date
    Enum.each(reminder_dates, fn date ->
      schedule_handle_notification(Map.put(base_notification, :step, "reminder"), date, "discord")
      schedule_handle_notification(Map.put(base_notification, :step, "reminder"), date, "email")
    end)

    # Schedule the final "after" notification for the deletion date
    schedule_handle_notification(
      Map.put(base_notification, :step, "after"),
      scheduled_at,
      "discord"
    )

    schedule_handle_notification(
      Map.put(base_notification, :step, "after"),
      scheduled_at,
      "email"
    )

    response
  end

  def schedule_handle_notification(attrs, scheduled_at, channel) do
    template = Sanbase.Notifications.get_template(attrs.action, attrs.step, channel)

    notification_attrs = %{
      action: attrs.action,
      params: attrs.params,
      channel: channel,
      step: attrs.step,
      status: "scheduled",
      scheduled_at: scheduled_at,
      metric_registry_id: attrs.metric_registry_id,
      notification_template_id: template.id,
      is_manual: Map.get(attrs, :is_manual, false)
    }

    multi =
      Ecto.Multi.new()
      |> Ecto.Multi.run(:notification, fn _repo, _changes ->
        Notification.create(notification_attrs)
      end)
      |> Ecto.Multi.run(:oban_job, fn _repo, %{notification: notification} ->
        job_args =
          case channel do
            "discord" ->
              %{
                notification_id: notification.id,
                action: notification.action,
                params: notification.params,
                channel: notification.channel,
                step: notification.step,
                template_id: notification.notification_template_id
              }

            "email" ->
              %{
                type: "change_status",
                notification_id: notification.id,
                new_status: "available"
              }
          end

        job =
          Sanbase.Notifications.Workers.ProcessNotification.new(job_args,
            scheduled_at: scheduled_at
          )

        {:ok, %{id: job_id}} = Oban.insert(@oban_conf_name, job)
        {:ok, job_id}
      end)
      |> Ecto.Multi.run(:update_notification, fn _repo,
                                                 %{notification: notification, oban_job: job_id} ->
        Notification.update(notification, %{job_id: job_id})
      end)

    case Repo.transaction(multi) do
      {:ok, %{update_notification: notification}} -> notification
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  def handle_notification(%{action: action, params: params} = attrs) do
    channels = @default_channels[action]
    step = Map.get(attrs, :step, "all")

    Enum.map(channels, fn channel ->
      case channel do
        "discord" -> handle_discord_notification(action, step, params, attrs)
        "email" -> handle_email_notification(action, step, params, attrs)
        _ -> :ok
      end
    end)
  end

  defp handle_discord_notification(action, step, params, attrs) do
    template = Sanbase.Notifications.get_template(action, step, "discord")

    notification_attrs = %{
      action: action,
      params: params,
      channel: "discord",
      step: step,
      status: "available",
      metric_registry_id: attrs[:metric_registry_id],
      notification_template_id: template.id,
      is_manual: Map.get(attrs, :is_manual, false)
    }

    multi =
      Ecto.Multi.new()
      |> Ecto.Multi.run(:notification, fn _repo, _changes ->
        Notification.create(notification_attrs)
      end)
      |> Ecto.Multi.run(:oban_job, fn _repo, %{notification: notification} ->
        job_args = %{
          notification_id: notification.id,
          action: notification.action,
          params: notification.params,
          channel: notification.channel,
          step: notification.step,
          template_id: notification.notification_template_id
        }

        job =
          Sanbase.Notifications.Workers.ProcessNotification.new(job_args,
            scheduled_at: seconds_after(5)
          )

        {:ok, %{id: job_id}} = Oban.insert(@oban_conf_name, job)

        {:ok, job_id}
      end)
      |> Ecto.Multi.run(:update_notification, fn _repo,
                                                 %{notification: notification, oban_job: job_id} ->
        Notification.update(notification, %{job_id: job_id})
      end)

    multi
    |> Repo.transaction()
    |> case do
      {:ok, %{update_notification: notification}} -> notification
      {:ok, %{notification: notification}} -> notification
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  defp handle_email_notification(action, step, params, attrs) do
    template = Sanbase.Notifications.get_template(action, step, "email", "text/html")

    notification_attrs = %{
      action: action,
      params: params,
      channel: "email",
      step: step,
      status: "available",
      metric_registry_id: attrs[:metric_registry_id],
      notification_template_id: template.id,
      is_manual: Map.get(attrs, :is_manual, false)
    }

    multi =
      Ecto.Multi.new()
      |> Ecto.Multi.run(:notification, fn _repo, _changes ->
        Notification.create(notification_attrs)
      end)

    multi
    |> Repo.transaction()
    |> case do
      {:ok, %{notification: notification}} -> notification
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  def handle_manual_notification(attrs) do
    channel = attrs.channel
    params = attrs.params

    if channel == "email" do
      if not Map.has_key?(params, :content) or not Map.has_key?(params, :subject) do
        raise "Email notification requires content and subject"
      end
    end

    if channel == "discord" do
      if not Map.has_key?(params, :content) do
        raise "Discord notification requires content"
      end

      if not Map.has_key?(params, :discord_channel) do
        raise "Discord notification requires discord_channel"
      end
    end

    notification_attrs = %{
      action: "message",
      params: params,
      channel: channel,
      step: "all",
      status: "available",
      is_manual: true
    }

    multi =
      Ecto.Multi.new()
      |> Ecto.Multi.run(:notification, fn _repo, _changes ->
        Notification.create(notification_attrs)
      end)
      |> Ecto.Multi.run(:oban_job, fn _repo, %{notification: notification} ->
        job_args = %{
          notification_id: notification.id,
          action: notification.action,
          params: notification.params,
          channel: notification.channel,
          step: notification.step,
          is_manual: true
        }

        job =
          Sanbase.Notifications.Workers.ProcessNotification.new(job_args,
            scheduled_at: seconds_after(5)
          )

        {:ok, %{id: job_id}} = Oban.insert(@oban_conf_name, job)

        {:ok, job_id}
      end)
      |> Ecto.Multi.run(:update_notification, fn _repo,
                                                 %{notification: notification, oban_job: job_id} ->
        Notification.update(notification, %{job_id: job_id})
      end)

    multi
    |> Repo.transaction()
    |> case do
      {:ok, %{update_notification: notification}} -> {:ok, notification}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  def should_notify_metric_event?(metric_registry_id) do
    {:ok, metric_registry} = Sanbase.Metric.Registry.by_id(metric_registry_id)
    deploy_env = Sanbase.Utils.Config.module_get(Sanbase, :deployment_env)
    metric_registry.exposed_environments in [deploy_env, "all"] or deploy_env in ["dev", "test"]
  end

  def fetch_last_version(schema, id) do
    Repo.one(
      from(v in Sanbase.Version,
        where: v.entity_id == ^id,
        where: v.entity_schema == ^schema,
        order_by: [desc: v.recorded_at],
        limit: 1
      )
    )
  end

  defp cancel_scheduled_notifications(metric_registry_id) do
    all_scheduled_notifications =
      from(n in Notification,
        where: n.metric_registry_id == ^metric_registry_id and n.status == "scheduled"
      )

    all_job_ids = from(n in all_scheduled_notifications, select: n.job_id) |> Repo.all()

    # Cancel all Oban jobs
    if all_job_ids != [] do
      query = Oban.Job |> where([j], j.id in ^all_job_ids)
      Oban.cancel_all_jobs(:oban_web, query)
    end

    # Update notification statuses to cancelled
    Sanbase.Repo.update_all(all_scheduled_notifications, set: [status: "cancelled"])

    :ok
  end
end
