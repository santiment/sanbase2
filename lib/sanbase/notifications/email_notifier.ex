defmodule Sanbase.Notifications.EmailNotifier do
  import Ecto.Query
  import Sanbase.DateTimeUtils, only: [seconds_after: 1]

  alias Sanbase.{Repo, Notifications.Notification}

  def oban_conf_name do
    Sanbase.ApplicationUtils.container_type()
    |> case do
      "all" -> :oban_web
      # web, admin, scrapers
      container_type -> String.to_existing_atom("oban_#{container_type}")
    end
  end

  def send_daily_digest(action) do
    notifications = get_unprocessed_notifications(action)

    if Enum.any?(notifications) do
      send_digest_email(notifications, action)
    end
  end

  defp send_digest_email(notifications, action) do
    notifications_groups = group_notifications(notifications, action)

    Enum.each(notifications_groups, fn {_key, group_notifications} ->
      all_params = combine_notification_params(group_notifications)
      notification_ids = Enum.map(group_notifications, & &1.id)

      job =
        %{
          channel: "email",
          action: action,
          notification_ids: notification_ids,
          params: all_params,
          step: List.first(group_notifications).step
        }
        |> Sanbase.Notifications.Workers.ProcessNotification.new(scheduled_at: seconds_after(5))

      {:ok, %{id: job_id}} = Oban.insert(oban_conf_name(), job)

      # update all notifications with the job_id
      Enum.each(group_notifications, &Notification.update(&1, %{job_id: job_id}))
    end)
  end

  def group_notifications(notifications, "metric_deleted") do
    notifications
    |> Enum.group_by(fn notification ->
      {notification.step, notification.params["scheduled_at"]}
    end)
  end

  def group_notifications(notifications, _action) do
    %{{nil, nil} => notifications}
  end

  def get_unprocessed_notifications(action) do
    yesterday = DateTime.utc_now() |> DateTime.add(-24, :hour)

    Notification
    |> where([n], n.channel == "email")
    |> where([n], n.status == "available")
    |> where([n], n.inserted_at >= ^yesterday)
    |> where([n], n.action == ^action)
    |> Repo.all()
  end

  def combine_notification_params(notifications) do
    notifications
    |> Enum.reduce(%{}, fn notification, acc ->
      metrics = (acc["metrics_list"] || []) ++ (notification.params["metrics_list"] || [])
      acc = Map.put(acc, "metrics_list", metrics)

      case notification.params["scheduled_at"] do
        nil -> acc
        scheduled_at -> Map.put(acc, "scheduled_at", scheduled_at)
      end
    end)
  end
end
