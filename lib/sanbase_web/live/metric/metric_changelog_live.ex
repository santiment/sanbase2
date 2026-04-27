defmodule SanbaseWeb.MetricChangelogLive do
  use SanbaseWeb, :live_view

  alias Sanbase.Metric.Registry.MetricVersions

  @initial_limit 20
  @load_more_increment 20

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Metrics Changelog")
     |> assign(:search_term, "")
     |> assign(:changelog_entries, [])
     |> assign(:has_more, false)
     |> assign(:offset, 0)
     |> assign(:limit, @initial_limit)
     |> assign(:loading, true)}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    send(self(), :load_initial_data)
    {:noreply, socket}
  end

  @impl true
  def handle_info(:load_initial_data, socket) do
    search_term = socket.assigns.search_term
    limit = socket.assigns.limit
    offset = 0

    {changelog_entries, has_more, _total_dates} =
      MetricVersions.get_changelog_by_date(limit, offset, search_term)

    {:noreply,
     socket
     |> assign(:changelog_entries, changelog_entries)
     |> assign(:has_more, has_more)
     |> assign(:offset, offset + length(changelog_entries))
     |> assign(:loading, false)}
  end

  @impl true
  def handle_info(:load_more_data, socket) do
    search_term = socket.assigns.search_term
    limit = @load_more_increment
    offset = socket.assigns.offset

    {new_entries, has_more, _total_dates} =
      MetricVersions.get_changelog_by_date(limit, offset, search_term)

    updated_entries = socket.assigns.changelog_entries ++ new_entries

    {:noreply,
     socket
     |> assign(:changelog_entries, updated_entries)
     |> assign(:has_more, has_more)
     |> assign(:offset, offset + length(new_entries))
     |> assign(:loading, false)}
  end

  @impl true
  def handle_event("suggest", %{"search" => %{"term" => search_term}}, socket) do
    {:noreply, assign(socket, :search_term, search_term)}
  end

  @impl true
  def handle_event("clear_search", _, socket) do
    # Clear search and reload the data
    send(self(), :load_initial_data)

    {:noreply,
     socket
     |> assign(:search_term, "")
     |> assign(:changelog_entries, [])
     |> assign(:offset, 0)
     |> assign(:loading, true)}
  end

  @impl true
  def handle_event("search", %{"search" => %{"term" => search_term}}, socket) do
    # Reset pagination and load with new search term
    limit = @initial_limit
    offset = 0

    {changelog_entries, has_more, _total_dates} =
      MetricVersions.get_changelog_by_date(limit, offset, search_term)

    {:noreply,
     socket
     |> assign(:search_term, search_term)
     |> assign(:changelog_entries, changelog_entries)
     |> assign(:has_more, has_more)
     |> assign(:offset, offset + length(changelog_entries))
     |> assign(:loading, false)}
  end

  @impl true
  def handle_event("load_more", _params, socket) do
    if socket.assigns.has_more and not socket.assigns.loading do
      send(self(), :load_more_data)
      {:noreply, assign(socket, :loading, true)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto px-4 py-8">
      <div class="flex justify-between items-center mb-6">
        <h1 class="text-2xl font-bold">{@page_title}</h1>
      </div>

      <div class="card bg-base-100 border border-base-300 shadow p-6">
        <div class="mb-6">
          <div class="flex justify-between items-center mb-4">
            <h3 class="text-lg font-semibold">Metrics Changelog</h3>
            <div class="text-sm">
              <span class="inline-flex items-center mr-3">
                <span class="h-3 w-3 bg-success rounded-full mr-1"></span> Newly added metrics
              </span>
              <span class="inline-flex items-center">
                <span class="h-3 w-3 bg-warning rounded-full mr-1"></span> Deprecated metrics
              </span>
            </div>
          </div>

          <.search_form search_term={@search_term} />
        </div>

        <div id="changelog-entries" phx-update="replace" class="space-y-8 mb-8">
          <.changelog_entry
            :for={entry <- @changelog_entries}
            entry={entry}
            id={"date-#{entry.date}"}
          />
        </div>

        <.loading_spinner :if={@loading} />

        <div
          :if={@has_more && !@loading}
          id="infinite-scroll-marker"
          phx-hook="InfiniteScroll"
          class="h-4 w-full"
        >
        </div>

        <div
          :if={!@has_more && !@loading && Enum.empty?(@changelog_entries)}
          class="text-center py-10"
        >
          <p class="text-base-content/50">No changelog entries found.</p>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders the search form.
  """
  attr :search_term, :string, required: true, doc: "Current search term"

  def search_form(assigns) do
    ~H"""
    <form phx-submit="search" phx-change="suggest" class="mb-4">
      <div class="join w-full">
        <div class="relative flex-grow">
          <input
            type="text"
            name="search[term]"
            value={@search_term}
            placeholder="Search by metric name..."
            phx-debounce="300"
            class="input join-item w-full"
          />
          <%= if String.length(@search_term) > 0 do %>
            <button
              type="button"
              phx-click="clear_search"
              class="absolute inset-y-0 right-0 pr-3 flex items-center text-base-content/50 hover:text-base-content"
            >
              <.icon name="hero-x-mark" class="size-5" />
            </button>
          <% end %>
        </div>
        <button type="submit" class="btn btn-primary join-item">Search</button>
      </div>
    </form>
    """
  end

  @doc """
  Renders a loading spinner.
  """
  def loading_spinner(assigns) do
    ~H"""
    <div class="flex justify-center items-center py-10">
      <span class="loading loading-spinner loading-lg text-primary"></span>
    </div>
    """
  end

  @doc """
  Renders a single changelog entry for a specific date.
  """
  attr :entry, :map,
    required: true,
    doc: "The changelog entry containing created and deprecated metrics for a date"

  attr :id, :string, required: true, doc: "A unique ID for the entry (for phx-update)"

  def changelog_entry(assigns) do
    ~H"""
    <div id={@id} class="border-b border-base-300 pb-6 last:border-b-0">
      <h3 class="text-xl font-semibold mb-4">
        {format_date(@entry.date)}
      </h3>

      <div class="space-y-6">
        <div :if={length(@entry.created_metrics) > 0} class="space-y-2">
          <div class="flex items-center mb-2">
            <span class="badge badge-sm badge-success badge-soft">Newly added metrics</span>
          </div>
          <div class="space-y-2">
            <.metric_event
              :for={%{metric: metric, event: event} <- @entry.created_metrics}
              metric={metric}
              event={event}
              type={:created}
            />
          </div>
        </div>

        <div :if={length(@entry.deprecated_metrics) > 0} class="space-y-2">
          <div class="flex items-center mb-2">
            <span class="badge badge-sm badge-warning badge-soft">Deprecated metrics</span>
          </div>
          <div class="space-y-2">
            <.metric_event
              :for={%{metric: metric, event: event, note: note} <- @entry.deprecated_metrics}
              metric={metric}
              event={event}
              type={:deprecated}
              note={note}
            />
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a compact, single-line metric event.
  """
  attr :metric, :map, required: true, doc: "The metric data"
  attr :event, :map, required: true, doc: "The event data"
  attr :type, :atom, required: true, doc: "The type of event (:created or :deprecated)"
  attr :note, :string, default: nil, doc: "Optional deprecation note"

  def metric_event(assigns) do
    ~H"""
    <div class={"flex items-center py-2 pl-3 border-l-4 hover:bg-base-200 #{if @type == :created, do: "border-success", else: "border-warning"}"}>
      <div class="flex-grow">
        <div class="flex items-center">
          <span class="font-medium text-primary mr-2">{@metric.human_readable_name}</span>
          <code class="kbd kbd-xs">{@metric.metric}</code>
          <span :if={has_docs?(@metric)} class="ml-2">
            <a href={get_first_doc_link(@metric)} target="_blank" class="link link-primary">
              <.icon name="hero-arrow-top-right-on-square" class="size-4 inline" />
            </a>
          </span>
        </div>
        <div :if={@note && @type == :deprecated} class="mt-1 text-sm text-warning">
          <span class="font-medium">Note:</span> {@note}
        </div>
      </div>
    </div>
    """
  end

  # Helper functions
  defp format_date(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> Calendar.strftime(date, "%B %d, %Y")
      _ -> date_string
    end
  end

  defp has_docs?(metric) do
    metric.docs && metric.docs != []
  end

  defp get_first_doc_link(metric) do
    if has_docs?(metric) do
      doc = List.first(metric.docs)
      doc.link
    else
      "#"
    end
  end
end
