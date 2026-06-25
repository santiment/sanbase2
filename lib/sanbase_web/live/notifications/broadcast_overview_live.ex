defmodule SanbaseWeb.NotificationsLive.BroadcastOverviewLive do
  use SanbaseWeb, :live_view

  alias Sanbase.AppNotifications
  alias Sanbase.Admin.Permissions

  @impl true
  def mount(_params, _session, socket) do
    broadcasts = AppNotifications.list_broadcast_notifications()

    socket =
      socket
      |> assign(:page_title, "Broadcast Notifications Overview")
      |> assign(:can_delete, can_delete?(socket))
      |> assign(:confirming, nil)
      |> stream(:broadcasts, broadcasts)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col justify-center w-full px-4">
      <div class="flex justify-between items-center mb-6">
        <h1 class="text-2xl">{@page_title}</h1>
        <div class="flex gap-3">
          <.link href={~p"/admin/notifications/broadcast"} class="btn btn-sm btn-primary">
            <.icon name="hero-megaphone" class="size-4" /> New Broadcast
          </.link>
          <.link href={~p"/admin/generic?resource=sanbase_notifications"} class="btn btn-sm btn-soft">
            All Notifications
          </.link>
        </div>
      </div>

      <div class="rounded-box border border-base-300 overflow-x-auto">
        <table class="table table-zebra table-sm">
          <thead>
            <tr>
              <th>ID</th>
              <th>Title</th>
              <th>Content</th>
              <th>Type</th>
              <th>Recipients</th>
              <th>Read</th>
              <th>Unread</th>
              <th>Created</th>
              <th class="sticky right-0 z-10 bg-base-200 border-l border-base-300">Actions</th>
            </tr>
          </thead>
          <tbody id="broadcasts" phx-update="stream">
            <tr id="broadcasts-empty" class="hidden only:block">
              <td colspan="9" class="px-4 py-8 text-center text-base-content/40">
                No broadcast notifications found. Use the "New Broadcast" button to create one.
              </td>
            </tr>
            <tr :for={{id, b} <- @streams.broadcasts} id={id}>
              <td class="font-medium">
                <.link
                  href={~p"/admin/generic/#{b.id}?resource=sanbase_notifications"}
                  class="link link-primary"
                >
                  {b.id}
                </.link>
              </td>
              <td class="max-w-[200px] truncate">{b.title}</td>
              <td class="max-w-[300px] truncate">{truncate_content(b.content)}</td>
              <td>
                <span class="badge badge-sm badge-info badge-soft">{b.type}</span>
              </td>
              <td class="text-center">
                <span class="font-semibold">{b.recipients_count}</span>
              </td>
              <td class="text-center">
                <span class="font-semibold text-success">{b.read_count}</span>
              </td>
              <td class="text-center">
                <span class={[
                  "font-semibold",
                  if(b.unread_count > 0, do: "text-warning", else: "text-success")
                ]}>
                  {b.unread_count}
                </span>
              </td>
              <td class="whitespace-nowrap text-xs">{format_datetime(b.inserted_at)}</td>
              <td class="sticky right-0 z-10 bg-base-100 border-l border-base-300">
                <div class="flex gap-2">
                  <.link href={recipients_url(b.id)} class="btn btn-xs btn-soft btn-info">
                    <.icon name="hero-users" class="size-3.5" /> View Recipients
                  </.link>
                  <button
                    :if={@can_delete}
                    type="button"
                    phx-click="request_delete"
                    phx-value-id={b.id}
                    phx-value-title={b.title}
                    phx-value-recipients={b.recipients_count}
                    class="btn btn-xs btn-soft btn-error"
                  >
                    <.icon name="hero-trash" class="size-3.5" /> Delete
                  </button>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <.modal
        :if={@confirming}
        id="confirm-delete-broadcast"
        show
        on_cancel={JS.push("cancel_delete")}
      >
        <h3 class="text-lg font-semibold">Delete this broadcast?</h3>
        <p class="py-4 text-sm">
          <span class="font-medium">"{@confirming.title}"</span>
          will immediately disappear from all
          <span class="font-semibold">{@confirming.recipients}</span>
          recipients' notifications. This can be undone by an engineer.
        </p>
        <div class="flex justify-end gap-2">
          <button type="button" class="btn btn-sm btn-ghost" phx-click={JS.push("cancel_delete")}>
            Cancel
          </button>
          <button type="button" class="btn btn-sm btn-error" phx-click="confirm_delete">
            <.icon name="hero-trash" class="size-4" /> Delete broadcast
          </button>
        </div>
      </.modal>
    </div>
    """
  end

  @impl true
  def handle_event("request_delete", %{"id" => id} = params, socket) do
    if can_delete?(socket) do
      confirming = %{
        id: String.to_integer(id),
        title: params["title"] || "",
        recipients: params["recipients"] || "0"
      }

      {:noreply, assign(socket, :confirming, confirming)}
    else
      {:noreply, deny_delete(socket)}
    end
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, :confirming, nil)}
  end

  def handle_event("confirm_delete", _params, socket) do
    with true <- can_delete?(socket),
         %{id: id} <- socket.assigns.confirming,
         {:ok, _notification} <- AppNotifications.soft_delete_broadcast_notification(id) do
      {:noreply,
       socket
       |> assign(:confirming, nil)
       |> put_flash(:info, "Broadcast deleted. It no longer appears for any user.")
       |> stream_delete_by_dom_id(:broadcasts, "broadcasts-#{id}")}
    else
      false ->
        {:noreply, deny_delete(socket)}

      nil ->
        {:noreply, assign(socket, :confirming, nil)}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> assign(:confirming, nil)
         |> put_flash(:error, "Broadcast not found.")}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> assign(:confirming, nil)
         |> put_flash(:error, "Could not delete broadcast. Please try again.")}
    end
  end

  # Editor and Owner can delete; Viewer cannot. Mirrors the generic admin's
  # delete gating (Sanbase.Admin.Permissions.can?(:delete, ...)).
  defp can_delete?(socket) do
    Permissions.can?(:delete, roles: socket.assigns[:current_user_role_names] || [])
  end

  defp deny_delete(socket) do
    socket
    |> assign(:confirming, nil)
    |> put_flash(:error, "You don't have permission to delete broadcasts.")
  end

  defp recipients_url(notification_id) do
    "/admin/generic/search?" <>
      URI.encode_query(%{
        "resource" => "sanbase_notification_read_statuses",
        "search[filters][0][field]" => "notification_id",
        "search[filters][0][value]" => to_string(notification_id)
      })
  end

  defp truncate_content(nil), do: ""

  defp truncate_content(content) when byte_size(content) > 80 do
    String.slice(content, 0, 80) <> "..."
  end

  defp truncate_content(content), do: content

  defp format_datetime(dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  end
end
