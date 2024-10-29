defmodule Sanbase.NotificationsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Sanbase.Notifications` context.
  """

  alias Sanbase.Notifications

  @doc """
  Generate a notification_action.
  """
  def notification_action_fixture(attrs \\ %{}) do
    attrs
    |> Enum.into(%{
      status: :pending,
      action_type: :create,
      scheduled_at: ~U[2024-10-17 07:48:00Z],
      requires_verification: true,
      verified: true
    })
    |> Notifications.create_notification_action()
  end

  @doc """
  Generate a notification.
  """
  def notification_fixture(attrs \\ %{}) do
    # Create the notification action first
    {:ok, notification_action} = notification_action_fixture()

    # Merge the provided attrs with default attrs, ensuring notification_action_id is set
    attrs
    |> Enum.into(%{
      status: :pending,
      step: :once,
      # Changed to use only valid channel
      channels: [:discord],
      # Make sure this is set
      notification_action_id: notification_action.id,
      scheduled_at: ~U[2024-10-17 07:56:00Z],
      sent_at: ~U[2024-10-17 07:56:00Z],
      content: "some content",
      display_in_ui: true,
      template_params: %{}
    })
    |> Notifications.create_notification()
  end

  @doc """
  Creates all the default notification templates needed for testing.
  """
  def create_default_templates do
    # Create template
    notification_template_fixture(%{
      channel: "all",
      action_type: "create",
      step: "once",
      template: """
      In the latest update the following metrics have been added:
      {{metrics_list}}
      For more information, please visit #changelog
      """
    })

    # Update templates
    notification_template_fixture(%{
      channel: "all",
      action_type: "update",
      step: "before",
      template: """
      In order to make our data more precise, we're going to run a recalculation of the following metrics:
      {{metrics_list}}
      This will be done on {{scheduled_at}} and will take approximately {{duration}}
      """
    })

    notification_template_fixture(%{
      channel: "all",
      action_type: "update",
      step: "after",
      template: """
      Recalculation of the following metrics has been completed successfully:
      {{metrics_list}}
      """
    })

    # Delete templates
    notification_template_fixture(%{
      channel: "all",
      action_type: "delete",
      step: "before",
      template: """
      Due to lack of usage, we made a decision to deprecate the following metrics:
      {{metrics_list}}
      This is planned to take place on {{scheduled_at}}. Please make sure that you adjust your data consumption accordingly. If you have strong objections, please contact us.
      """
    })

    notification_template_fixture(%{
      channel: "all",
      action_type: "delete",
      step: "reminder",
      template: """
      This is a reminder about the scheduled deprecation of the following metrics:
      {{metrics_list}}
      It will happen on {{scheduled_at}}. Please make sure to adjust accordingly.
      """
    })

    notification_template_fixture(%{
      channel: "all",
      action_type: "delete",
      step: "after",
      template: """
      Deprecation of the following metrics has been completed successfully:
      {{metrics_list}}
      """
    })

    # Alert templates
    notification_template_fixture(%{
      channel: "all",
      action_type: "alert",
      step: "detected",
      template: """
      Metric delay alert: {{metric_name}} is experiencing a delay due to technical issues. Affected assets: {{asset_categories}}
      """
    })

    notification_template_fixture(%{
      channel: "all",
      action_type: "alert",
      step: "resolved",
      template: """
      Metric delay resolved: {{metric_name}} is back to normal
      """
    })
  end

  @doc """
  Generate a notification_template.
  """
  def notification_template_fixture(attrs \\ %{}) do
    attrs
    |> Enum.into(%{
      action_type: "some action_type",
      channel: "all",
      step: "some step",
      template: "some template"
    })
    |> Sanbase.Notifications.create_notification_template()
  end
end
