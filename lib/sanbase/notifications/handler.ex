defmodule Sanbase.Notifications.Handler do
  import Ecto.Query
  import Sanbase.DateTimeUtils, only: [seconds_after: 1]

  alias Sanbase.{Repo, Notifications.Notification}

  @oban_conf_name :oban_web

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

    handle_notification(%{
      action: "metric_created",
      step: "all",
      params: %{metrics_list: [metric]},
      metric_registry_id: event.data.id
    })
  end

  def handle_metric_registry_updated_event(event) do
    id = event.data.id

    last_version =
      Repo.one(
        from(v in Sanbase.Version,
          where: v.entity_id == ^id,
          where: v.entity_schema == ^Sanbase.Metric.Registry,
          order_by: [desc: v.recorded_at],
          limit: 1
        )
      )

    case last_version.patch do
      %{hard_deprecate_after: {:changed, {:primitive_change, _old, new_date}}} ->
        base_notification = %{
          action: "metric_deleted",
          params: %{
            metrics_list: [event.data.metric],
            scheduled_at: new_date
          },
          metric_registry_id: id
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
    reminder_date = DateTime.add(new_date, -3 * 24 * 60 * 60, :second)
    schedule_handle_notification(Map.put(base_notification, :step, "reminder"), reminder_date)

    schedule_handle_notification(Map.put(base_notification, :step, "after"), scheduled_at)

    response
  end

  def schedule_handle_notification(attrs, scheduled_at) do
    Oban.insert(
      @oban_conf_name,
      Sanbase.Notifications.Workers.HandleNotificationWorker.new(attrs,
        scheduled_at: scheduled_at
      )
    )
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
    template = Sanbase.Notifications.get_template(action, step, "discord") |> dbg()

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
    template = Sanbase.Notifications.get_template(action, step, "email")

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
end
