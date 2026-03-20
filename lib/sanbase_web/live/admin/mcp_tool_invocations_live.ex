defmodule SanbaseWeb.Admin.McpToolInvocationsLive do
  use SanbaseWeb, :live_view

  alias Sanbase.MCP.ToolInvocation

  @page_size 50

  @impl true
  def mount(_params, _session, socket) do
    stats = ToolInvocation.stats_since(DateTime.add(DateTime.utc_now(), -24 * 3600, :second))
    tool_names = ToolInvocation.tool_names()

    socket =
      socket
      |> assign(:page_title, "MCP Tool Invocations")
      |> assign(:tool_name_filter, "")
      |> assign(:email_search, "")
      |> assign(:metric_search, "")
      |> assign(:page, 1)
      |> assign(:page_size, @page_size)
      |> assign(:stats, stats)
      |> assign(:tool_names, tool_names)
      |> assign(:expanded_id, nil)
      |> load_invocations()

    {:ok, socket}
  end

  @impl true
  def handle_event("filter_tool_name", %{"tool_name" => tool_name}, socket) do
    {:noreply,
     socket
     |> assign(:tool_name_filter, tool_name)
     |> assign(:page, 1)
     |> load_invocations()}
  end

  def handle_event("search_email", %{"email_search" => search}, socket) do
    {:noreply,
     socket
     |> assign(:email_search, search)
     |> assign(:page, 1)
     |> load_invocations()}
  end

  def handle_event("filter_metric", %{"metric_search" => metric}, socket) do
    {:noreply,
     socket
     |> assign(:metric_search, metric)
     |> assign(:page, 1)
     |> load_invocations()}
  end

  def handle_event("next_page", _, socket) do
    page = min(socket.assigns.page + 1, socket.assigns.total_pages)

    {:noreply,
     socket
     |> assign(:page, page)
     |> load_invocations()}
  end

  def handle_event("prev_page", _, socket) do
    page = max(1, socket.assigns.page - 1)

    {:noreply,
     socket
     |> assign(:page, page)
     |> load_invocations()}
  end

  def handle_event("toggle_raw", %{"id" => id}, socket) do
    id = String.to_integer(id)
    expanded_id = if socket.assigns.expanded_id == id, do: nil, else: id
    {:noreply, assign(socket, :expanded_id, expanded_id)}
  end

  defp load_invocations(socket) do
    opts = filter_opts(socket.assigns)
    invocations = ToolInvocation.list_invocations(opts)
    total = ToolInvocation.count_invocations(opts)
    total_pages = max(1, ceil(total / socket.assigns.page_size))

    socket
    |> assign(:invocations, invocations)
    |> assign(:total_count, total)
    |> assign(:total_pages, total_pages)
  end

  defp filter_opts(assigns) do
    [
      tool_name: assigns.tool_name_filter,
      email_search: assigns.email_search,
      metric: assigns.metric_search,
      page: assigns.page,
      page_size: assigns.page_size
    ]
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col w-full px-4 py-6">
      <h1 class="text-2xl font-bold text-gray-800 mb-6">{@page_title}</h1>

      <.stats_bar stats={@stats} />

      <div class="flex flex-col sm:flex-row gap-4 mb-6">
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">Tool Name</label>
          <select
            id="tool-name-filter"
            phx-change="filter_tool_name"
            name="tool_name"
            class="rounded-lg border border-zinc-300 px-3 py-2 text-sm text-zinc-900 focus:border-zinc-400 focus:ring-0"
          >
            <option value="">All Tools</option>
            <option :for={tn <- @tool_names} value={tn} selected={tn == @tool_name_filter}>
              {tn}
            </option>
          </select>
        </div>

        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">Search User Email</label>
          <form phx-change="search_email" phx-submit="search_email" id="email-search-form">
            <input
              type="text"
              name="email_search"
              id="email-search-input"
              value={@email_search}
              placeholder="Search by email..."
              phx-debounce="300"
              class="rounded-lg border border-zinc-300 px-3 py-2 text-sm text-zinc-900 focus:border-zinc-400 focus:ring-0 w-72"
            />
          </form>
        </div>

        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">Search Metric</label>
          <form phx-change="filter_metric" phx-submit="filter_metric" id="metric-search-form">
            <input
              type="text"
              name="metric_search"
              id="metric-search-input"
              value={@metric_search}
              placeholder="Filter by metric..."
              phx-debounce="300"
              class="rounded-lg border border-zinc-300 px-3 py-2 text-sm text-zinc-900 focus:border-zinc-400 focus:ring-0 w-72"
            />
          </form>
        </div>

        <div class="flex items-end">
          <span class="text-sm text-gray-500">
            {if @total_count > 0,
              do: "#{@total_count} invocations found",
              else: "No invocations found"}
          </span>
        </div>
      </div>

      <div class="bg-white shadow rounded-lg overflow-hidden">
        <table class="min-w-full divide-y divide-gray-200">
          <thead class="bg-gray-50">
            <tr>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Timestamp
              </th>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                User
              </th>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Tool Name
              </th>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Metrics
              </th>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Slugs
              </th>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Duration (ms)
              </th>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Response Size
              </th>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Status
              </th>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Expand
              </th>
            </tr>
          </thead>
          <tbody class="bg-white divide-y divide-gray-200">
            <tr :if={@invocations == []}>
              <td colspan="9" class="px-4 py-8 text-sm text-gray-500 text-center">
                No invocations found matching your filters.
              </td>
            </tr>
            <tr :for={inv <- @invocations} id={"inv-#{inv.id}"} class="hover:bg-gray-50">
              <td class="px-4 py-3 whitespace-nowrap text-sm text-gray-500">
                {format_datetime(inv.inserted_at)}
              </td>
              <td class="px-4 py-3 whitespace-nowrap text-sm text-gray-900 font-mono">
                {if inv.user, do: inv.user.email, else: "Anonymous"}
              </td>
              <td class="px-4 py-3 whitespace-nowrap text-sm">
                <.tool_badge tool_name={inv.tool_name} />
              </td>
              <td class="px-4 py-3 text-sm text-gray-500">
                {Enum.join(inv.metrics, ", ")}
              </td>
              <td class="px-4 py-3 text-sm text-gray-500">
                {Enum.join(inv.slugs, ", ")}
              </td>
              <td class="px-4 py-3 whitespace-nowrap text-sm text-gray-500">
                {inv.duration_ms}
              </td>
              <td class="px-4 py-3 whitespace-nowrap text-sm text-gray-500">
                {format_bytes(inv.response_size_bytes)}
              </td>
              <td class="px-4 py-3 whitespace-nowrap text-sm">
                <.status_badge is_successful={inv.is_successful} />
              </td>
              <td class="px-4 py-3 whitespace-nowrap text-sm">
                <button
                  phx-click="toggle_raw"
                  phx-value-id={inv.id}
                  class="text-blue-600 hover:text-blue-800 text-xs"
                >
                  {if @expanded_id == inv.id, do: "Hide", else: "Show"}
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <.expanded_panel :if={@expanded_id} invocations={@invocations} expanded_id={@expanded_id} />

      <.pagination page={@page} total_pages={@total_pages} total_count={@total_count} />
    </div>
    """
  end

  defp stats_bar(assigns) do
    ~H"""
    <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3 mb-6">
      <.stat_card
        :for={{tool_name, count} <- Enum.sort_by(@stats, fn {_, c} -> -c end)}
        label={tool_name}
        count={count}
      />
    </div>
    """
  end

  defp stat_card(assigns) do
    ~H"""
    <div class="rounded-lg border p-3 bg-blue-50 border-blue-200">
      <div class="text-2xl font-bold text-blue-700">{@count}</div>
      <div class="text-xs text-gray-500 truncate" title={@label}>{@label} (24h)</div>
    </div>
    """
  end

  defp tool_badge(assigns) do
    ~H"""
    <span class="px-2 py-1 text-xs font-semibold rounded-full bg-indigo-100 text-indigo-800">
      {@tool_name}
    </span>
    """
  end

  defp status_badge(assigns) do
    {text, class} =
      if assigns.is_successful,
        do: {"OK", "bg-green-100 text-green-800"},
        else: {"Error", "bg-red-100 text-red-800"}

    assigns = assign(assigns, text: text, badge_class: class)

    ~H"""
    <span class={["px-2 py-1 text-xs font-semibold rounded-full", @badge_class]}>
      {@text}
    </span>
    """
  end

  defp expanded_panel(assigns) do
    inv = Enum.find(assigns.invocations, &(&1.id == assigns.expanded_id))
    assigns = assign(assigns, :inv, inv)

    ~H"""
    <div
      :if={@inv}
      class="mt-4 bg-gray-900 text-green-300 rounded-lg p-4 text-xs font-mono overflow-x-auto"
    >
      <div class="mb-2 text-gray-400">
        Params for invocation #{@inv.id} ({@inv.tool_name})
      </div>
      <pre>{Jason.encode!(@inv.params || %{}, pretty: true)}</pre>
      <div :if={@inv.error_message} class="mt-3 text-red-400">
        <div class="mb-1 text-gray-400">Error message:</div>
        <pre>{@inv.error_message}</pre>
      </div>
    </div>
    """
  end

  defp pagination(assigns) do
    ~H"""
    <div :if={@total_pages > 1} class="flex items-center justify-between mt-4 px-2">
      <button
        phx-click="prev_page"
        disabled={@page <= 1}
        class={[
          "px-3 py-1 text-sm rounded border",
          if(@page <= 1,
            do: "text-gray-300 border-gray-200 cursor-not-allowed",
            else: "text-gray-700 border-gray-300 hover:bg-gray-50"
          )
        ]}
      >
        Previous
      </button>

      <span class="text-sm text-gray-600">
        Page {@page} of {@total_pages}
      </span>

      <button
        phx-click="next_page"
        disabled={@page >= @total_pages}
        class={[
          "px-3 py-1 text-sm rounded border",
          if(@page >= @total_pages,
            do: "text-gray-300 border-gray-200 cursor-not-allowed",
            else: "text-gray-700 border-gray-300 hover:bg-gray-50"
          )
        ]}
      >
        Next
      </button>
    </div>
    """
  end

  defp format_datetime(nil), do: "-"

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")
  end

  defp format_bytes(nil), do: "-"
  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1024, 1)} KB"
end
