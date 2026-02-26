defmodule SanbaseWeb.NotificationsLive.BroadcastNotificationFormLive do
  use SanbaseWeb, :live_view

  alias Sanbase.AppNotifications

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       form:
         to_form(%{
           "title" => "",
           "content" => ""
         })
     )}
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto">
      <div class="flex items-center justify-between mb-4">
        <.link
          navigate={~p"/admin/generic?resource=sanbase_notifications"}
          class="text-sm text-gray-600 hover:text-gray-900"
        >
          ← Back to Notifications
        </.link>
        <h2 class="text-xl font-bold">Broadcast App Notification</h2>
      </div>

      <p class="text-sm text-gray-600 mb-4">
        This will create an in-app notification visible to all registered users.
        The notification will appear in their notification feed.
      </p>

      <.form for={@form} phx-submit="send_broadcast">
        <div class="space-y-4">
          <div>
            <.input
              field={@form[:title]}
              type="text"
              label="Title"
              placeholder="Enter notification title..."
              required
            />
          </div>

          <div>
            <.input
              field={@form[:content]}
              type="textarea"
              label="Content"
              placeholder="Enter notification content..."
              required
            />
          </div>

          <div>
            <.button type="submit" phx-disable-with="Broadcasting...">
              Broadcast to All Users
            </.button>
          </div>
        </div>
      </.form>
    </div>
    """
  end

  def handle_event("send_broadcast", %{"title" => title, "content" => content}, socket) do
    if String.trim(title) == "" or String.trim(content) == "" do
      {:noreply, put_flash(socket, :error, "Title and content are required")}
    else
      case AppNotifications.create_broadcast_notification(%{
             type: "system_notification",
             title: title,
             content: content
           }) do
        {:ok, %{recipients_count: count}} ->
          {:noreply,
           socket
           |> put_flash(:info, "Notification broadcast to #{count} users successfully!")
           |> assign(form: to_form(%{"title" => "", "content" => ""}))}

        {:error, reason} ->
          {:noreply,
           put_flash(socket, :error, "Failed to broadcast notification: #{inspect(reason)}")}
      end
    end
  end
end
