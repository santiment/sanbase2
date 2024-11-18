defmodule Sanbase.Notifications.EmailNotifier do
  import Ecto.Query
  alias Sanbase.{Repo, Notifications.Notification}
  alias Sanbase.Notifications.TemplateRenderer

  @metric_updates_list :metric_updates
  @subject "Sanbase Metric Updates"

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

      content =
        TemplateRenderer.render_content(%{
          action: action,
          params: all_params,
          step: List.first(group_notifications).step,
          channel: "email"
        })

      case mailjet_api().send_to_list(@metric_updates_list, @subject, content, []) do
        :ok -> Enum.each(group_notifications, &mark_processed(&1, :email))
        {:error, _reason} -> :error
      end
    end)
  end

  defp group_notifications(notifications, "metric_deleted") do
    notifications
    |> Enum.group_by(fn notification ->
      {notification.step, notification.params["scheduled_at"]}
    end)
  end

  defp group_notifications(notifications, _action) do
    %{{nil, nil} => notifications}
  end

  defp get_unprocessed_notifications(action) do
    yesterday = DateTime.utc_now() |> DateTime.add(-24, :hour)

    Notification
    |> where([n], "email" in n.channels)
    |> where([n], n.processed_for_email == false)
    |> where([n], n.inserted_at >= ^yesterday)
    |> where([n], n.action == ^action)
    |> Repo.all()
  end

  defp combine_notification_params(notifications) do
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

  defp mark_processed(notification, channel) do
    notification
    |> Notification.mark_channel_processed(channel)
    |> Repo.update()
  end

  def mailjet_api do
    Application.get_env(:sanbase, :mailjet_api, Sanbase.Email.MailjetApi)
  end
end
