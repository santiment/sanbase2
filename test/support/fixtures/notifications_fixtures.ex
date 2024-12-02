defmodule Sanbase.NotificationsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Sanbase.Notifications` context.
  """

  @doc """
  Creates all the default notification templates needed for testing.
  """
  def create_default_templates do
    # Create template
    notification_template_fixture(%{
      channel: "all",
      action: "create",
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
      action: "update",
      step: "before",
      template: """
      In order to make our data more precise, we're going to run a recalculation of the following metrics:
      {{metrics_list}}
      This will be done on {{scheduled_at}} and will take approximately {{duration}}
      """
    })

    notification_template_fixture(%{
      channel: "all",
      action: "update",
      step: "after",
      template: """
      Recalculation of the following metrics has been completed successfully:
      {{metrics_list}}
      """
    })

    # Delete templates
    notification_template_fixture(%{
      channel: "all",
      action: "delete",
      step: "before",
      template: """
      Due to lack of usage, we made a decision to deprecate the following metrics:
      {{metrics_list}}
      This is planned to take place on {{scheduled_at}}. Please make sure that you adjust your data consumption accordingly. If you have strong objections, please contact us.
      """
    })

    notification_template_fixture(%{
      channel: "all",
      action: "delete",
      step: "reminder",
      template: """
      This is a reminder about the scheduled deprecation of the following metrics:
      {{metrics_list}}
      It will happen on {{scheduled_at}}. Please make sure to adjust accordingly.
      """
    })

    notification_template_fixture(%{
      channel: "all",
      action: "delete",
      step: "after",
      template: """
      Deprecation of the following metrics has been completed successfully:
      {{metrics_list}}
      """
    })

    # Metric Created templates for Discord
    notification_template_fixture(%{
      channel: "discord",
      action: "metric_created",
      step: "all",
      template: """
      In the latest update the following metrics have been added:
      {{metrics_list}}
      For more information, please visit #changelog
      """
    })

    # Metric Deleted templates for Discord
    notification_template_fixture(%{
      channel: "discord",
      action: "metric_deleted",
      step: "before",
      template: """
      Due to lack of usage, we made a decision to deprecate the following metrics:
      {{metrics_list}}
      This is planned to take place on {{scheduled_at}}. Please make sure that you adjust your data consumption accordingly.
      """
    })

    notification_template_fixture(%{
      channel: "discord",
      action: "metric_deleted",
      step: "reminder",
      template: """
      This is a reminder about the scheduled deprecation of the following metrics:
      {{metrics_list}}
      It will happen on {{scheduled_at}}. Please make sure to adjust accordingly.
      """
    })

    notification_template_fixture(%{
      channel: "discord",
      action: "metric_deleted",
      step: "after",
      template: """
      Deprecation of the following metrics has been completed successfully:
      {{metrics_list}}
      """
    })

    # Email templates
    notification_template_fixture(%{
      channel: "email",
      action: "metric_created",
      step: "all",
      template: """
      In the latest update the following metrics have been added:
      {{metrics_list}}
      For more information, please visit #changelog
      """
    })

    notification_template_fixture(%{
      channel: "email",
      action: "metric_deleted",
      step: "before",
      template: """
      Due to lack of usage, we made a decision to deprecate the following metrics:
      {{metrics_list}}
      This is planned to take place on {{scheduled_at}}. Please make sure to adjust your data consumption accordingly.
      """
    })

    notification_template_fixture(%{
      channel: "email",
      action: "metric_deleted",
      step: "all",
      template: """
      The following metrics have been scheduled for deprecation:
      {{metrics_list}}
      This is planned to take place on {{scheduled_at}}. Please make sure to adjust your data consumption accordingly.
      """
    })

    # Alert templates
    notification_template_fixture(%{
      channel: "discord",
      action: "alert",
      step: "detected",
      template: """
      Metric delay alert: {{metric_name}} is experiencing a delay due to technical issues. Affected assets: {{asset_categories}}
      """
    })

    notification_template_fixture(%{
      channel: "discord",
      action: "alert",
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
      action: "some action",
      channel: "all",
      step: "some step",
      template: "some template"
    })
    |> Sanbase.Notifications.create_notification_template()
  end
end
