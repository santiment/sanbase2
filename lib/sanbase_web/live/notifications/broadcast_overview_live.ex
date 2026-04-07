defmodule SanbaseWeb.NotificationsLive.BroadcastOverviewLive do
  use SanbaseWeb, :live_view

  alias Sanbase.AppNotifications

  @impl true
  def mount(_params, _session, socket) do
    broadcasts = AppNotifications.list_broadcast_notifications()

    {:ok,
     assign(socket,
       page_title: "Broadcast Notifications Overview",
       broadcasts: broadcasts
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col justify-center w-full px-4">
      <div class="flex justify-between items-center mb-6">
        <h1 class="text-gray-800 text-2xl">{@page_title}</h1>
        <div class="flex gap-3">
          <.link
            href={~p"/admin/notifications/broadcast"}
            class="inline-flex items-center px-4 py-2 text-sm font-medium text-white bg-blue-600 rounded-lg hover:bg-blue-700"
          >
            <.icon name="hero-megaphone" class="w-4 h-4 mr-2" /> New Broadcast
          </.link>
          <.link
            href={~p"/admin/generic?resource=sanbase_notifications"}
            class="inline-flex items-center px-4 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-lg hover:bg-gray-50"
          >
            All Notifications
          </.link>
        </div>
      </div>

      <div class="overflow-x-auto shadow-md sm:rounded-lg">
        <table class="min-w-full text-sm text-left text-gray-500">
          <thead class="text-xs text-gray-700 uppercase bg-gray-50">
            <tr>
              <th scope="col" class="px-4 py-3">ID</th>
              <th scope="col" class="px-4 py-3">Title</th>
              <th scope="col" class="px-4 py-3">Content</th>
              <th scope="col" class="px-4 py-3">Type</th>
              <th scope="col" class="px-4 py-3">Recipients</th>
              <th scope="col" class="px-4 py-3">Unread</th>
              <th scope="col" class="px-4 py-3">Created</th>
              <th scope="col" class="px-4 py-3">Actions</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={b <- @broadcasts} class="bg-white border-b hover:bg-gray-50">
              <td class="px-4 py-3 font-medium text-gray-900">
                <.link
                  href={~p"/admin/generic/#{b.id}?resource=sanbase_notifications"}
                  class="text-blue-600 hover:text-blue-800 underline"
                >
                  {b.id}
                </.link>
              </td>
              <td class="px-4 py-3 max-w-[200px] truncate">{b.title}</td>
              <td class="px-4 py-3 max-w-[300px] truncate">{truncate_content(b.content)}</td>
              <td class="px-4 py-3">
                <span class="px-2 py-1 text-xs font-semibold rounded-full bg-blue-100 text-blue-800">
                  {b.type}
                </span>
              </td>
              <td class="px-4 py-3 text-center">
                <span class="font-semibold text-gray-900">{b.recipients_count}</span>
              </td>
              <td class="px-4 py-3 text-center">
                <span class={[
                  "font-semibold",
                  if(b.unread_count > 0, do: "text-amber-600", else: "text-green-600")
                ]}>
                  {b.unread_count}
                </span>
              </td>
              <td class="px-4 py-3 whitespace-nowrap text-xs">
                {format_datetime(b.inserted_at)}
              </td>
              <td class="px-4 py-3">
                <.link
                  href={recipients_url(b.id)}
                  class="inline-flex items-center px-3 py-1.5 text-xs font-medium text-blue-700 bg-blue-50 border border-blue-200 rounded-lg hover:bg-blue-100"
                >
                  <.icon name="hero-users" class="w-3.5 h-3.5 mr-1.5" /> View Recipients
                </.link>
              </td>
            </tr>
            <tr :if={@broadcasts == []}>
              <td colspan="8" class="px-4 py-8 text-center text-gray-400">
                No broadcast notifications found. Use the "New Broadcast" button to create one.
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
