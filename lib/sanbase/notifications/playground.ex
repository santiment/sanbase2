defmodule Sanbase.Notifications.Playground do
  alias Sanbase.Notifications

  @doc """
  Creates a notification action with a notification and optional email notification.

  Example:
    iex> Sanbase.Notifications.Playground.create_delete_notification(
      ["Daily Active Addresses", "Network Growth"],
      "December 25, 2024, 10:00 AM UTC",
      :before
    )
  """
  def create_delete_notification(metrics_list, scheduled_at_str, step) do
    {:ok, notification_action} =
      Notifications.create_notification_action(%{
        action_type: :delete,
        scheduled_at: DateTime.utc_now(),
        status: :pending,
        requires_verification: false,
        verified: true
      })

    {:ok, notification} =
      Notifications.create_notification(%{
        notification_action_id: notification_action.id,
        step: step,
        scheduled_at: get_scheduled_at(step),
        channels: [:discord, :email],
        content: "---",
        template_params: %{
          "scheduled_at" => scheduled_at_str,
          "metrics_list" => metrics_list
        }
      })

    # Render the content using the template
    content = Sanbase.Notifications.TemplateRenderer.render_content(notification)
    {:ok, notification} = Notifications.update_notification(notification, %{content: content})

    {:ok, notification_action, notification}
  end

  @doc """
  Creates an alert notification for metric delays.

  Example:
    iex> Sanbase.Notifications.Playground.create_alert_notification(
      "Daily Active Addresses",
      ["ERC-20", "Stablecoins"],
      :detected
    )
  """
  def create_alert_notification(metric_name, asset_categories, step)
      when step in [:detected, :resolved] do
    {:ok, notification_action} =
      Notifications.create_notification_action(%{
        action_type: :alert,
        scheduled_at: DateTime.utc_now(),
        status: :pending,
        requires_verification: false,
        verified: true
      })

    template_params =
      case step do
        :detected ->
          %{
            "metric_name" => metric_name,
            "asset_categories" => asset_categories
          }

        :resolved ->
          %{
            "metric_name" => metric_name
          }
      end

    {:ok, notification} =
      Notifications.create_notification(%{
        notification_action_id: notification_action.id,
        step: step,
        scheduled_at: DateTime.utc_now(),
        channels: [:discord],
        content: "---",
        template_params: template_params
      })

    # Render the content using the template
    content =
      notification
      |> Map.put(:notification_action, notification_action)
      |> Sanbase.Notifications.TemplateRenderer.render_content()

    {:ok, notification} = Notifications.update_notification(notification, %{content: content})

    {:ok, notification_action, notification}
  end

  @doc """
  Creates a manual notification with custom text.

  Example:
    iex> Sanbase.Notifications.Playground.create_manual_notification(
      "Important: API maintenance scheduled for tomorrow at 10 AM UTC"
    )
  """
  def create_manual_notification(custom_text) do
    {:ok, notification_action} =
      Notifications.create_notification_action(%{
        action_type: :manual,
        scheduled_at: DateTime.utc_now(),
        status: :pending,
        requires_verification: false,
        verified: true
      })

    {:ok, notification} =
      Notifications.create_notification(%{
        notification_action_id: notification_action.id,
        step: :once,
        status: :pending,
        scheduled_at: DateTime.utc_now(),
        channels: [:discord],
        display_in_ui: true,
        content: custom_text
      })

    {:ok, notification_action, notification}
  end

  # Helper functions
  defp get_scheduled_at(:before), do: DateTime.utc_now()
  defp get_scheduled_at(:reminder), do: DateTime.add(DateTime.utc_now(), 3600 * 24 * 27, :second)
  defp get_scheduled_at(:after), do: DateTime.add(DateTime.utc_now(), 3600 * 24 * 30, :second)
end
