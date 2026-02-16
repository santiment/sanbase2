defmodule SanbaseWeb.Admin.SesEventsLive do
  use SanbaseWeb, :live_view

  alias Sanbase.Email
  alias Sanbase.Email.SesEmailEvent

  @page_size 50

  @impl true
  def mount(_params, _session, socket) do
    stats = Email.ses_event_stats_since(DateTime.add(DateTime.utc_now(), -24 * 3600, :second))

    socket =
      socket
      |> assign(:page_title, "SES Email Events")
      |> assign(:event_type_filter, "")
      |> assign(:email_search, "")
      |> assign(:page, 1)
      |> assign(:page_size, @page_size)
      |> assign(:stats, stats)
      |> assign(:expanded_id, nil)
      |> load_events()

    {:ok, socket}
  end

  @impl true
  def handle_event("filter_event_type", %{"event_type" => event_type}, socket) do
    {:noreply,
     socket
     |> assign(:event_type_filter, event_type)
     |> assign(:page, 1)
     |> load_events()}
  end

  def handle_event("search_email", %{"email_search" => search}, socket) do
    {:noreply,
     socket
     |> assign(:email_search, search)
     |> assign(:page, 1)
     |> load_events()}
  end

  def handle_event("next_page", _, socket) do
    page = min(socket.assigns.page + 1, socket.assigns.total_pages)

    {:noreply,
     socket
     |> assign(:page, page)
     |> load_events()}
  end

  def handle_event("prev_page", _, socket) do
    page = max(1, socket.assigns.page - 1)

    {:noreply,
     socket
     |> assign(:page, page)
     |> load_events()}
  end

  def handle_event("toggle_raw", %{"id" => id}, socket) do
    id = String.to_integer(id)

    expanded_id =
      if socket.assigns.expanded_id == id, do: nil, else: id

    {:noreply, assign(socket, :expanded_id, expanded_id)}
  end

  defp load_events(socket) do
    opts = filter_opts(socket.assigns)
    events = Email.list_ses_events(opts)
    total = Email.count_ses_events(opts)
    total_pages = max(1, ceil(total / socket.assigns.page_size))

    socket
    |> assign(:events, events)
    |> assign(:total_count, total)
    |> assign(:total_pages, total_pages)
  end

  defp filter_opts(assigns) do
    [
      event_type: assigns.event_type_filter,
      email_search: assigns.email_search,
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
          <label class="block text-sm font-medium text-gray-700 mb-1">Event Type</label>
          <select
            id="event-type-filter"
            phx-change="filter_event_type"
            name="event_type"
            class="rounded-lg border border-zinc-300 px-3 py-2 text-sm text-zinc-900 focus:border-zinc-400 focus:ring-0"
          >
            <option value="">All Events</option>
            <option
              :for={et <- SesEmailEvent.event_types()}
              value={et}
              selected={et == @event_type_filter}
            >
              {et}
            </option>
          </select>
        </div>

        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">Search Email</label>
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

        <div class="flex items-end">
          <span class="text-sm text-gray-500">
            {if @total_count > 0, do: "#{@total_count} events found", else: "No events found"}
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
                Email
              </th>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Event
              </th>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Details
              </th>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Message ID
              </th>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Raw
              </th>
            </tr>
          </thead>
          <tbody class="bg-white divide-y divide-gray-200">
            <tr :if={@events == []}>
              <td colspan="6" class="px-4 py-8 text-sm text-gray-500 text-center">
                No events found matching your filters.
              </td>
            </tr>
            <tr :for={event <- @events} id={"event-#{event.id}"} class="hover:bg-gray-50">
              <td class="px-4 py-3 whitespace-nowrap text-sm text-gray-500">
                {format_datetime(event.timestamp)}
              </td>
              <td class="px-4 py-3 whitespace-nowrap text-sm text-gray-900 font-mono">
                {event.email}
              </td>
              <td class="px-4 py-3 whitespace-nowrap text-sm">
                <.event_badge event_type={event.event_type} />
              </td>
              <td class="px-4 py-3 text-sm text-gray-500">
                <.event_details event={event} />
              </td>
              <td class="px-4 py-3 whitespace-nowrap text-sm text-gray-400 font-mono text-xs">
                {String.slice(event.message_id || "", 0, 20)}...
              </td>
              <td class="px-4 py-3 whitespace-nowrap text-sm">
                <button
                  phx-click="toggle_raw"
                  phx-value-id={event.id}
                  class="text-blue-600 hover:text-blue-800 text-xs"
                >
                  {if @expanded_id == event.id, do: "Hide", else: "Show"}
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <.raw_data_panel :if={@expanded_id} events={@events} expanded_id={@expanded_id} />

      <.pagination page={@page} total_pages={@total_pages} total_count={@total_count} />
    </div>
    """
  end

  defp stats_bar(assigns) do
    ~H"""
    <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3 mb-6">
      <.stat_card label="Send" count={Map.get(@stats, "Send", 0)} color="blue" />
      <.stat_card label="Delivery" count={Map.get(@stats, "Delivery", 0)} color="green" />
      <.stat_card label="Bounce" count={Map.get(@stats, "Bounce", 0)} color="red" />
      <.stat_card label="Complaint" count={Map.get(@stats, "Complaint", 0)} color="orange" />
      <.stat_card label="Reject" count={Map.get(@stats, "Reject", 0)} color="purple" />
      <.stat_card label="Delay" count={Map.get(@stats, "DeliveryDelay", 0)} color="yellow" />
    </div>
    """
  end

  defp stat_card(assigns) do
    bg_class =
      case assigns.color do
        "blue" -> "bg-blue-50 border-blue-200"
        "green" -> "bg-green-50 border-green-200"
        "red" -> "bg-red-50 border-red-200"
        "orange" -> "bg-orange-50 border-orange-200"
        "purple" -> "bg-purple-50 border-purple-200"
        "yellow" -> "bg-yellow-50 border-yellow-200"
        _ -> "bg-gray-50 border-gray-200"
      end

    text_class =
      case assigns.color do
        "blue" -> "text-blue-700"
        "green" -> "text-green-700"
        "red" -> "text-red-700"
        "orange" -> "text-orange-700"
        "purple" -> "text-purple-700"
        "yellow" -> "text-yellow-700"
        _ -> "text-gray-700"
      end

    assigns = assign(assigns, bg_class: bg_class, text_class: text_class)

    ~H"""
    <div class={["rounded-lg border p-3", @bg_class]}>
      <div class={["text-2xl font-bold", @text_class]}>{@count}</div>
      <div class="text-xs text-gray-500">{@label} (24h)</div>
    </div>
    """
  end

  defp event_badge(assigns) do
    badge_class =
      case assigns.event_type do
        "Send" -> "bg-blue-100 text-blue-800"
        "Delivery" -> "bg-green-100 text-green-800"
        "Bounce" -> "bg-red-100 text-red-800"
        "Complaint" -> "bg-orange-100 text-orange-800"
        "Reject" -> "bg-purple-100 text-purple-800"
        "DeliveryDelay" -> "bg-yellow-100 text-yellow-800"
        _ -> "bg-gray-100 text-gray-800"
      end

    assigns = assign(assigns, :badge_class, badge_class)

    ~H"""
    <span class={["px-2 py-1 text-xs font-semibold rounded-full", @badge_class]}>
      {@event_type}
    </span>
    """
  end

  defp event_details(assigns) do
    ~H"""
    <span :if={@event.bounce_type}>
      {Phoenix.Naming.humanize(@event.bounce_type)}
      <span :if={@event.bounce_sub_type} class="text-gray-400">
        / {Phoenix.Naming.humanize(@event.bounce_sub_type)}
      </span>
    </span>
    <span :if={@event.complaint_feedback_type}>
      {Phoenix.Naming.humanize(@event.complaint_feedback_type)}
    </span>
    <span :if={@event.reject_reason}>{@event.reject_reason}</span>
    <span :if={@event.delay_type}>{Phoenix.Naming.humanize(@event.delay_type)}</span>
    <span :if={@event.smtp_response} class="text-xs font-mono">
      {String.slice(@event.smtp_response, 0, 40)}
    </span>
    """
  end

  defp raw_data_panel(assigns) do
    event = Enum.find(assigns.events, &(&1.id == assigns.expanded_id))
    assigns = assign(assigns, :event, event)

    ~H"""
    <div
      :if={@event}
      class="mt-4 bg-gray-900 text-green-300 rounded-lg p-4 text-xs font-mono overflow-x-auto"
    >
      <div class="mb-2 text-gray-400">
        Raw data for event #{@event.id} ({@event.event_type} - {@event.email})
      </div>
      <pre>{Jason.encode!(@event.raw_data || %{}, pretty: true)}</pre>
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
end
