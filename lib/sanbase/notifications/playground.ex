defmodule Sanbase.Notifications.Playground do
  alias Sanbase.Notifications.Handler
  alias Sanbase.Notifications.EmailNotifier

  def test_metric_created_notification do
    Handler.handle_notification(%{
      action: "metric_created",
      params: %{metrics_list: ["metric A", "metric B"]}
    })
  end

  def test_metric_deleted_notification do
    Handler.handle_notification(%{
      action: "metric_deleted",
      params: %{metrics_list: ["metric A"], scheduled_at: ~U[2024-11-29 12:00:00Z]}
    })
  end

  def test_metric_deleted_notification2 do
    Handler.handle_notification(%{
      action: "metric_deleted",
      params: %{metrics_list: ["metric A"], scheduled_at: ~U[2024-11-30 12:00:00Z]}
    })
  end

  def test_metric_deleted_notification3 do
    Handler.handle_notification(%{
      action: "metric_deleted",
      params: %{metrics_list: ["metric C"], scheduled_at: ~U[2024-11-30 12:00:00Z]}
    })
  end

  def test_manual_notification do
    Handler.handle_notification(%{
      action: "manual",
      params: %{
        discord_text: "Hello, world!",
        email_text: "Hello, world!",
        email_subject: "Test email"
      }
    })
  end

  def test_alert_notification do
    Handler.handle_notification(%{
      action: "alert",
      params: %{
        metric_name: "Metric XYZ",
        asset_categories: ["Category A", "Category B"]
      },
      step: "detected"
    })
  end

  def test_alert_notification2 do
    Handler.handle_notification(%{
      action: "alert",
      params: %{
        metric_name: "Metric XYZ",
        asset_categories: ["Category A", "Category B"]
      },
      step: "resolved"
    })
  end

  def test_metric_created_email_notifier do
    EmailNotifier.send_daily_digest("metric_created")
  end

  def test_metric_deleted_email_notifier do
    EmailNotifier.send_daily_digest("metric_deleted")
  end
end
