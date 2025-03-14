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
    yesterday = DateTime.utc_now() |> DateTime.add(-1000, :hour)

    Notification
    |> where([n], n.channel == "email")
    |> where([n], n.status == "available")
    |> where([n], n.inserted_at >= ^yesterday)
    |> where([n], n.action == ^action)
    |> Repo.all()
  end

  def combine_notification_params(notifications) do
    metric_registry_ids = extract_registry_ids(notifications)
    metric_registries = fetch_registries(metric_registry_ids)
    metric_docs_map = build_docs_map(metric_registries)

    notifications
    |> Enum.reduce(%{}, fn notification, acc ->
      metrics = (acc["metrics_list"] || []) ++ (notification.params["metrics_list"] || [])
      metrics_with_docs = add_docs_to_metrics(metrics, metric_docs_map)

      acc = Map.put(acc, "metrics_list", metrics_with_docs)
      acc = Map.put(acc, "metrics_docs_map", metric_docs_map)

      case notification.params["scheduled_at"] do
        nil -> acc
        scheduled_at -> Map.put(acc, "scheduled_at", scheduled_at)
      end
    end)
  end

  defp extract_registry_ids(notifications) do
    notifications
    |> Enum.map(& &1.metric_registry_id)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp fetch_registries(metric_registry_ids) do
    unless Enum.empty?(metric_registry_ids) do
      Sanbase.Metric.Registry.by_ids(metric_registry_ids)
    else
      []
    end
  end

  defp build_docs_map(metric_registries) do
    metric_registries
    |> Enum.flat_map(fn registry ->
      main_entry = {registry.metric, get_doc_links(registry.docs)}

      alias_entries =
        Enum.map(registry.aliases, fn alias_struct ->
          {alias_struct.name, get_doc_links(registry.docs)}
        end)

      [main_entry | alias_entries]
    end)
    |> Map.new()
  end

  defp add_docs_to_metrics(metrics, metric_docs_map) do
    metrics
    |> Enum.map(&to_string/1)
  end

  defp get_doc_links(docs) when is_list(docs) do
    Enum.map(docs, & &1.link)
  end

  defp get_doc_links(_), do: []
end
