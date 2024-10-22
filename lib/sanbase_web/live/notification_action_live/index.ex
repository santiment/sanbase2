defmodule SanbaseWeb.NotificationActionLive.Index do
  use SanbaseWeb, :live_view

  alias Sanbase.Notifications
  alias Sanbase.Notifications.NotificationAction

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream(socket, :notification_actions, Notifications.list_notification_actions())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Notification action")
    |> assign(:notification_action, Notifications.get_notification_action!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Notification action")
    |> assign(:notification_action, %NotificationAction{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Notification actions")
    |> assign(:notification_action, nil)
  end

  @impl true
  def handle_info(
        {SanbaseWeb.NotificationActionLive.FormComponent, {:saved, notification_action}},
        socket
      ) do
    {:noreply, stream_insert(socket, :notification_actions, notification_action)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    notification_action = Notifications.get_notification_action!(id)
    {:ok, _} = Notifications.delete_notification_action(notification_action)

    {:noreply, stream_delete(socket, :notification_actions, notification_action)}
  end
end
