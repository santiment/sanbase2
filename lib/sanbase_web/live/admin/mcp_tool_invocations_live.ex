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
      <h1 class="text-2xl font-bold mb-6">{@page_title}</h1>

      <.stats_bar stats={@stats} />

      <div class="flex flex-col sm:flex-row gap-4 mb-6">
        <fieldset class="fieldset">
          <legend class="fieldset-legend">Tool Name</legend>
          <select
            id="tool-name-filter"
            phx-change="filter_tool_name"
            name="tool_name"
            class="select select-sm"
          >
            <option value="">All Tools</option>
            <option :for={tn <- @tool_names} value={tn} selected={tn == @tool_name_filter}>
              {tn}
            </option>
          </select>
        </fieldset>

        <fieldset class="fieldset">
          <legend class="fieldset-legend">Search User Email</legend>
          <form phx-change="search_email" phx-submit="search_email" id="email-search-form">
            <input
              type="text"
              name="email_search"
              id="email-search-input"
              value={@email_search}
              placeholder="Search by email..."
              phx-debounce="300"
              class="input input-sm w-72"
            />
          </form>
        </fieldset>

        <fieldset class="fieldset">
          <legend class="fieldset-legend">Search Metric</legend>
          <form phx-change="filter_metric" phx-submit="filter_metric" id="metric-search-form">
            <input
              type="text"
              name="metric_search"
              id="metric-search-input"
              value={@metric_search}
              placeholder="Filter by metric..."
              phx-debounce="300"
              class="input input-sm w-72"
            />
          </form>
        </fieldset>

        <div class="flex items-end">
          <span class="text-sm text-base-content/60">
            {if @total_count > 0,
              do: "#{@total_count} invocations found",
              else: "No invocations found"}
          </span>
        </div>
      </div>

      <div class="rounded-box border border-base-300 overflow-hidden">
        <table class="table table-zebra table-sm">
          <thead>
            <tr>
              <th>Timestamp</th>
              <th>User</th>
              <th>Tool Name</th>
              <th>Metrics</th>
              <th>Slugs</th>
              <th>Duration (ms)</th>
              <th>Response Size</th>
              <th>Status</th>
              <th>Expand</th>
            </tr>
          </thead>
          <tbody>
            <tr :if={@invocations == []}>
              <td colspan="9" class="text-center text-base-content/60 py-6">
                No invocations found matching your filters.
              </td>
            </tr>
            <tr :for={inv <- @invocations} id={"inv-#{inv.id}"}>
              <td class="text-base-content/70">{format_datetime(inv.inserted_at)}</td>
              <td class="font-mono">
                {if inv.user, do: inv.user.email, else: "Anonymous"}
              </td>
              <td><.tool_badge tool_name={inv.tool_name} /></td>
              <td class="text-base-content/70">{Enum.join(inv.metrics, ", ")}</td>
              <td class="text-base-content/70">{Enum.join(inv.slugs, ", ")}</td>
              <td class="text-base-content/70">{inv.duration_ms}</td>
              <td class="text-base-content/70">{format_bytes(inv.response_size_bytes)}</td>
              <td><.status_badge is_successful={inv.is_successful} /></td>
              <td>
                <button
                  phx-click="toggle_raw"
                  phx-value-id={inv.id}
                  class="btn btn-xs btn-ghost link-primary"
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
    <div class="card bg-base-200 border border-base-300 p-3">
      <div class="text-2xl font-bold text-info">{@count}</div>
      <div class="text-xs text-base-content/60 truncate" title={@label}>{@label} (24h)</div>
    </div>
    """
  end

  defp tool_badge(assigns) do
    ~H"""
    <span class="badge badge-sm badge-secondary">{@tool_name}</span>
    """
  end

  defp status_badge(assigns) do
    {text, class} =
      if assigns.is_successful,
        do: {"OK", "badge-success"},
        else: {"Error", "badge-error"}

    assigns = assign(assigns, text: text, badge_class: class)

    ~H"""
    <span class={["badge badge-sm", @badge_class]}>{@text}</span>
    """
  end

  defp expanded_panel(assigns) do
    inv = Enum.find(assigns.invocations, &(&1.id == assigns.expanded_id))
    assigns = assign(assigns, :inv, inv)

    ~H"""
    <div
      :if={@inv}
      class="mt-4 mockup-code bg-neutral text-neutral-content rounded-box p-4 text-xs overflow-x-auto"
    >
      <div class="mb-2 text-neutral-content/60">
        Params for invocation #{@inv.id} ({@inv.tool_name})
      </div>
      <pre>{Jason.encode!(@inv.params || %{}, pretty: true)}</pre>
      <div :if={@inv.error_message} class="mt-3 text-error">
        <div class="mb-1 text-neutral-content/60">Error message:</div>
        <pre>{@inv.error_message}</pre>
      </div>
    </div>
    """
  end

  defp pagination(assigns) do
    ~H"""
    <div :if={@total_pages > 1} class="flex items-center justify-between mt-4 px-2">
      <button phx-click="prev_page" disabled={@page <= 1} class="btn btn-sm btn-soft">
        Previous
      </button>

      <span class="text-sm text-base-content/70">Page {@page} of {@total_pages}</span>

      <button phx-click="next_page" disabled={@page >= @total_pages} class="btn btn-sm btn-soft">
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
