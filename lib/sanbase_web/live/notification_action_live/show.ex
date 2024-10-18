defmodule SanbaseWeb.NotificationActionLive.Show do
  use SanbaseWeb, :live_view

  alias Sanbase.Notifications

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    {:noreply,
     socket
     |> assign(:page_title, page_title(socket.assigns.live_action))
     |> assign(:notification_action, Notifications.get_notification_action!(id))}
  end

  defp page_title(:show), do: "Show Notification action"
  defp page_title(:edit), do: "Edit Notification action"
end
