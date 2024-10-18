defmodule Sanbase.NotificationsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Sanbase.Notifications` context.
  """

  @doc """
  Generate a notification_action.
  """
  def notification_action_fixture(attrs \\ %{}) do
    {:ok, notification_action} =
      attrs
      |> Enum.into(%{
        action_type: "some action_type",
        requires_verification: true,
        scheduled_at: ~U[2024-10-17 07:48:00Z],
        status: "some status",
        verified: true
      })
      |> Sanbase.Notifications.create_notification_action()

    notification_action
  end

  @doc """
  Generate a notification.
  """
  def notification_fixture(attrs \\ %{}) do
    {:ok, notification} =
      attrs
      |> Enum.into(%{
        channels: ["option1", "option2"],
        content: "some content",
        display_in_ui: true,
        scheduled_at: ~U[2024-10-17 07:56:00Z],
        sent_at: ~U[2024-10-17 07:56:00Z],
        status: "some status",
        step: "some step",
        template_params: %{}
      })
      |> Sanbase.Notifications.create_notification()

    notification
  end
end
