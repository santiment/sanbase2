defmodule SanbaseWeb.NotificationsLive.BroadcastNotificationFormLive do
  use SanbaseWeb, :live_view

  alias Sanbase.AppNotifications

  def mount(_params, _session, socket) do
    broadcast_types = AppNotifications.broadcast_notification_types()
    {default_type, _label} = List.first(broadcast_types)

    {:ok,
     assign(socket,
       broadcast_types: broadcast_types,
       form:
         to_form(%{
           "title" => "",
           "content" => "",
           "type" => default_type
         })
     )}
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto">
      <div class="flex items-center justify-between mb-4">
        <div class="flex gap-4">
          <.link navigate={~p"/admin/admin_forms"} class="text-sm text-gray-600 hover:text-gray-900">
            ← Admin Forms
          </.link>
          <.link
            navigate={~p"/admin/generic?resource=sanbase_notifications"}
            class="text-sm text-gray-600 hover:text-gray-900"
          >
            ← Notifications
          </.link>
          <.link
            navigate={~p"/admin/generic?resource=sanbase_notification_read_statuses"}
            class="text-sm text-gray-600 hover:text-gray-900"
          >
            ← Read Statuses
          </.link>
        </div>
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
              field={@form[:type]}
              type="select"
              label="Notification Type"
              options={Enum.map(@broadcast_types, fn {value, label} -> {label, value} end)}
            />
          </div>

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

  def handle_event(
        "send_broadcast",
        %{"title" => title, "content" => content, "type" => type},
        socket
      ) do
    if String.trim(title) == "" or String.trim(content) == "" do
      {:noreply, put_flash(socket, :error, "Title and content are required")}
    else
      case AppNotifications.create_broadcast_notification(%{
             type: type,
             title: title,
             content: content
           }) do
        {:ok, %{recipients_count: count}} ->
          {default_type, _label} = List.first(socket.assigns.broadcast_types)

          {:noreply,
           socket
           |> put_flash(:info, "Notification broadcast to #{count} users successfully!")
           |> assign(form: to_form(%{"title" => "", "content" => "", "type" => default_type}))}

        {:error, reason} ->
          {:noreply,
           put_flash(socket, :error, "Failed to broadcast notification: #{inspect(reason)}")}
      end
    end
  end
end
