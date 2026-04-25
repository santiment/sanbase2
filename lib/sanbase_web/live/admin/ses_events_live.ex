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
      <h1 class="text-2xl font-bold mb-6">{@page_title}</h1>

      <.stats_bar stats={@stats} />

      <div class="flex flex-col sm:flex-row gap-4 mb-6">
        <fieldset class="fieldset">
          <legend class="fieldset-legend">Event Type</legend>
          <select
            id="event-type-filter"
            phx-change="filter_event_type"
            name="event_type"
            class="select select-sm"
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
        </fieldset>

        <fieldset class="fieldset">
          <legend class="fieldset-legend">Search Email</legend>
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

        <div class="flex items-end">
          <span class="text-sm text-base-content/60">
            {if @total_count > 0, do: "#{@total_count} events found", else: "No events found"}
          </span>
        </div>
      </div>

      <div class="rounded-box border border-base-300 overflow-hidden">
        <table class="table table-zebra table-sm">
          <thead>
            <tr>
              <th>Timestamp</th>
              <th>Email</th>
              <th>Event</th>
              <th>Details</th>
              <th>Message ID</th>
              <th>Raw</th>
            </tr>
          </thead>
          <tbody>
            <tr :if={@events == []}>
              <td colspan="6" class="text-center text-base-content/60 py-6">
                No events found matching your filters.
              </td>
            </tr>
            <tr :for={event <- @events} id={"event-#{event.id}"}>
              <td class="text-base-content/70">{format_datetime(event.timestamp)}</td>
              <td class="font-mono">{event.email}</td>
              <td>
                <.event_badge event_type={event.event_type} />
              </td>
              <td class="text-base-content/70">
                <.event_details event={event} />
              </td>
              <td class="font-mono text-xs text-base-content/50">
                {String.slice(event.message_id || "", 0, 20)}...
              </td>
              <td>
                <button phx-click="toggle_raw" phx-value-id={event.id} class="btn btn-xs btn-ghost link-primary">
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
    text_class =
      case assigns.color do
        "blue" -> "text-info"
        "green" -> "text-success"
        "red" -> "text-error"
        "orange" -> "text-warning"
        "purple" -> "text-secondary"
        "yellow" -> "text-warning"
        _ -> "text-base-content"
      end

    assigns = assign(assigns, text_class: text_class)

    ~H"""
    <div class="card bg-base-200 border border-base-300 p-3">
      <div class={["text-2xl font-bold", @text_class]}>{@count}</div>
      <div class="text-xs text-base-content/60">{@label} (24h)</div>
    </div>
    """
  end

  defp event_badge(assigns) do
    badge_class =
      case assigns.event_type do
        "Send" -> "badge-info"
        "Delivery" -> "badge-success"
        "Bounce" -> "badge-error"
        "Complaint" -> "badge-warning"
        "Reject" -> "badge-secondary"
        "DeliveryDelay" -> "badge-warning"
        _ -> "badge-ghost"
      end

    assigns = assign(assigns, :badge_class, badge_class)

    ~H"""
    <span class={["badge badge-sm", @badge_class]}>{@event_type}</span>
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
      class="mt-4 mockup-code bg-neutral text-neutral-content rounded-box p-4 text-xs overflow-x-auto"
    >
      <div class="mb-2 text-neutral-content/60">
        Raw data for event #{@event.id} ({@event.event_type} - {@event.email})
      </div>
      <pre>{Jason.encode!(@event.raw_data || %{}, pretty: true)}</pre>
    </div>
    """
  end

  defp pagination(assigns) do
    ~H"""
    <div :if={@total_pages > 1} class="flex items-center justify-between mt-4 px-2">
      <button phx-click="prev_page" disabled={@page <= 1} class="btn btn-sm btn-soft">
        Previous
      </button>

      <span class="text-sm text-base-content/70">
        Page {@page} of {@total_pages}
      </span>

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
end
