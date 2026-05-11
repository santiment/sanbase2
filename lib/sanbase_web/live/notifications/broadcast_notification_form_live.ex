defmodule SanbaseWeb.NotificationsLive.BroadcastNotificationFormLive do
  use SanbaseWeb, :live_view

  alias Sanbase.AppNotifications
  alias Sanbase.AppNotifications.Notification

  def mount(_params, _session, socket) do
    broadcast_types = AppNotifications.broadcast_notification_types()
    {default_type, _label} = List.first(broadcast_types)

    changeset =
      Notification.changeset(%Notification{}, %{type: default_type})
      |> Map.put(:action, :validate)

    {:ok,
     assign(socket,
       broadcast_types: broadcast_types,
       form: to_form(changeset, as: "notification")
     )}
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto p-6">
      <.link navigate={~p"/admin/admin_forms"} class="link link-hover text-sm mb-2 inline-block">
        ← Admin Forms
      </.link>
      <h1 class="text-3xl font-bold mb-2">Broadcast App Notification</h1>
      <p class="text-sm text-base-content/60 mb-4">
        This will create an in-app notification visible to all registered users.
        The notification will appear in their notification feed.
      </p>

      <div class="flex flex-wrap gap-2 mb-6">
        <.link navigate={~p"/admin/notifications/broadcast/overview"} class="btn btn-soft btn-sm">
          Broadcast Overview
        </.link>
        <.link
          navigate={~p"/admin/generic?resource=sanbase_notifications"}
          class="btn btn-soft btn-sm"
        >
          Notifications
        </.link>
        <.link
          navigate={~p"/admin/generic?resource=sanbase_notification_read_statuses"}
          class="btn btn-soft btn-sm"
        >
          Read Statuses
        </.link>
      </div>

      <.form for={@form} phx-change="validate" phx-submit="send_broadcast">
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
            <.input
              field={@form[:url]}
              type="text"
              label="URL (optional)"
              placeholder="e.g. /charts or https://academy.santiment.net/..."
              phx-debounce="300"
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

  def handle_event("validate", %{"notification" => params}, socket) do
    changeset =
      Notification.changeset(%Notification{}, params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: "notification"))}
  end

  def handle_event("send_broadcast", %{"notification" => params}, socket) do
    title = params["title"] |> to_string() |> String.trim()
    content = params["content"] |> to_string() |> String.trim()

    if title == "" or content == "" do
      {:noreply, put_flash(socket, :error, "Title and content are required")}
    else
      url = params["url"] |> to_string() |> String.trim()

      attrs = %{type: params["type"], title: title, content: content}
      attrs = if url != "", do: Map.put(attrs, :url, url), else: attrs

      case AppNotifications.create_broadcast_notification(attrs) do
        {:ok, %{recipients_count: count}} ->
          {default_type, _label} = List.first(socket.assigns.broadcast_types)

          changeset =
            Notification.changeset(%Notification{}, %{type: default_type})
            |> Map.put(:action, :validate)

          {:noreply,
           socket
           |> put_flash(:info, "Notification broadcast to #{count} users successfully!")
           |> assign(form: to_form(changeset, as: "notification"))}

        {:error, reason} ->
          {:noreply,
           put_flash(socket, :error, "Failed to broadcast notification: #{inspect(reason)}")}
      end
    end
  end
end
