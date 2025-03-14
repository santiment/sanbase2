defmodule Sanbase.Notifications.EmailNotifierTest do
  use Sanbase.DataCase, async: false

  alias Sanbase.Notifications.{Notification, EmailNotifier}
  alias Sanbase.Metric.Registry

  setup do
    {:ok, registry} = Registry.by_id(1)

    {:ok, notification} =
      Notification.create(%{
        action: "metric_created",
        params: %{
          "metrics_list" => [registry.metric]
        },
        channel: "email",
        metric_registry_id: registry.id
      })

    %{registry: registry, notification: notification}
  end

  describe "combine_notification_params/1" do
    test "adds documentation links to metrics", %{notification: notification, registry: registry} do
      # Call the function with our test notification
      result = EmailNotifier.combine_notification_params([notification])

      # Check that the metrics_list contains the expected format
      assert [metric_with_docs] = result["metrics_list"]
      assert metric_with_docs == "#{registry.metric} (#{hd(registry.docs).link})"
    end

    test "handles notifications without metric_registry_id" do
      # Create a notification without metric_registry_id
      {:ok, notification} =
        Notification.create(%{
          action: "metric_created",
          params: %{
            "metrics_list" => ["other_metric"]
          },
          channel: "email"
        })

      # Call the function with our test notification
      result = EmailNotifier.combine_notification_params([notification])

      # Check that the metrics_list contains the expected format
      assert [metric] = result["metrics_list"]
      assert metric == "other_metric"
    end

    test "handles multiple metrics from different notifications", %{registry: registry} do
      # Create two notifications with different metrics
      {:ok, notification1} =
        Notification.create(%{
          action: "metric_created",
          params: %{
            "metrics_list" => [registry.metric]
          },
          channel: "email"
        })

      {:ok, notification2} =
        Notification.create(%{
          action: "metric_created",
          params: %{
            "metrics_list" => [registry.metric]
          },
          channel: "email"
        })

      # Call the function with both notifications
      result = EmailNotifier.combine_notification_params([notification1, notification2])

      # Check that the metrics_list contains both metrics
      assert length(result["metrics_list"]) == 2

      assert registry.metric in result["metrics_list"]
    end
  end
end
