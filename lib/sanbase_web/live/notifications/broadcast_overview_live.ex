defmodule SanbaseWeb.NotificationsLive.BroadcastOverviewLive do
  use SanbaseWeb, :live_view

  alias Sanbase.AppNotifications

  @impl true
  def mount(_params, _session, socket) do
    broadcasts = AppNotifications.list_broadcast_notifications()

    socket =
      socket
      |> assign(:page_title, "Broadcast Notifications Overview")
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
              <th>Unread</th>
              <th>Created</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody id="broadcasts" phx-update="stream">
            <tr class="hidden only:block">
              <td colspan="8" class="px-4 py-8 text-center text-base-content/40">
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
                <span class={[
                  "font-semibold",
                  if(b.unread_count > 0, do: "text-warning", else: "text-success")
                ]}>
                  {b.unread_count}
                </span>
              </td>
              <td class="whitespace-nowrap text-xs">{format_datetime(b.inserted_at)}</td>
              <td>
                <.link href={recipients_url(b.id)} class="btn btn-xs btn-soft btn-info">
                  <.icon name="hero-users" class="size-3.5" /> View Recipients
                </.link>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
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
