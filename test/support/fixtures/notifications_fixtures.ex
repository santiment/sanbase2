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
end
