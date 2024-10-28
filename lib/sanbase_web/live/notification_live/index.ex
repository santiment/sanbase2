defmodule SanbaseWeb.NotificationLive.Index do
  use SanbaseWeb, :live_view

  alias Sanbase.Notifications
  alias Sanbase.Notifications.Notification

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream(socket, :notifications, Notifications.list_notifications())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Notification")
    |> assign(:notification, Notifications.get_notification!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Notification")
    |> assign(:notification, %Notification{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Notifications")
    |> assign(:notification, nil)
  end

  @impl true
  def handle_info({SanbaseWeb.NotificationLive.FormComponent, {:saved, notification}}, socket) do
    {:noreply, stream_insert(socket, :notifications, notification)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    notification = Notifications.get_notification!(id)
    {:ok, _} = Notifications.delete_notification(notification)

    {:noreply, stream_delete(socket, :notifications, notification)}
  end
end
