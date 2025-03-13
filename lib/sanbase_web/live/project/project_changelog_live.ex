defmodule SanbaseWeb.ProjectChangelogLive do
  use SanbaseWeb, :live_view

  alias Sanbase.Project
  alias Sanbase.Project.ProjectVersions
  alias Sanbase.ExAudit.Patch

  @dates_per_page 10

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Project Changelog")
     |> assign(:page, 1)
     |> assign(:search_term, "")
     |> assign(:changelog_entries, [])
     |> assign(:total_dates, 0)
     |> assign(:total_pages, 0)
     |> assign(:loading, true)}
  end

  @impl true
  def handle_params(%{"page" => page}, _uri, socket) do
    page = String.to_integer(page)
    search_term = socket.assigns.search_term

    # Use send_update to load data asynchronously
    send(self(), {:load_changelog_data, page, search_term})

    {:noreply,
     socket
     |> assign(:page, page)
     |> assign(:loading, true)}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    # Default to page 1 if no page parameter
    # Use send_update to load data asynchronously
    send(self(), {:load_changelog_data, 1, socket.assigns.search_term})

    {:noreply, socket}
  end

  @impl true
  def handle_info({:load_changelog_data, page, search_term}, socket) do
    {changelog_entries, total_dates} =
      ProjectVersions.get_changelog_by_date(page, @dates_per_page, search_term)

    total_pages = calculate_total_pages(total_dates)

    {:noreply,
     socket
     |> assign(:page, page)
     |> assign(:changelog_entries, changelog_entries)
     |> assign(:total_dates, total_dates)
     |> assign(:total_pages, total_pages)
     |> assign(:loading, false)}
  end

  @impl true
  def handle_event("search", %{"search" => %{"term" => search_term}}, socket) do
    # Use send_update to load data asynchronously
    send(self(), {:load_changelog_data, 1, search_term})

    {:noreply,
     socket
     |> assign(:search_term, search_term)
     |> assign(:page, 1)
     |> assign(:loading, true)}
  end

  @impl true
  def handle_event("change_page", %{"page" => page}, socket) do
    {:noreply, push_patch(socket, to: ~p"/admin/project_changelog?page=#{page}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto px-4 py-8">
      <h1 class="text-2xl font-bold mb-6">{@page_title}</h1>

      <.project_details :if={assigns[:project]} project={@project} events={@events} />
      <.changelog_list
        :if={!assigns[:project]}
        loading={@loading}
        changelog_entries={@changelog_entries}
        search_term={@search_term}
        page={@page}
        total_pages={@total_pages}
        total_dates={@total_dates}
      />
    </div>
    """
  end

  @doc """
  Renders the project details view with creation and hiding events.
  """
  attr :project, :map, required: true, doc: "The project to display details for"
  attr :events, :map, required: true, doc: "The creation and hiding events for the project"

  def project_details(assigns) do
    ~H"""
    <div class="mb-6">
      <.link navigate={~p"/admin/project_changelog"} class="text-blue-500 hover:underline">
        &larr; Back to changelog
      </.link>
    </div>

    <div class="bg-white shadow rounded-lg p-6 mb-6">
      <div class="flex items-center mb-4">
        <img
          :if={@project.logo_url}
          src={@project.logo_url}
          alt={@project.name}
          class="w-12 h-12 mr-4 rounded-full"
        />
        <div>
          <h2 class="text-xl font-bold">{@project.name}</h2>
          <p class="text-gray-600">{@project.ticker}</p>
          <p class="text-gray-500 text-sm">{@project.slug}</p>
        </div>
      </div>

      <p :if={@project.description} class="mb-4">{@project.description}</p>

      <.link
        href={Project.sanbase_link(@project)}
        target="_blank"
        class="text-blue-500 hover:underline"
      >
        View project page
      </.link>
    </div>

    <div class="bg-white shadow rounded-lg p-6">
      <h3 class="text-lg font-semibold mb-4">Changelog</h3>

      <div class="space-y-6">
        <.creation_event :if={@events.creation_event} event={@events.creation_event} />

        <.hiding_event :for={event <- @events.hiding_events} event={event} />

        <p
          :if={@events.creation_event == nil and @events.hiding_events == []}
          class="text-gray-500 italic"
        >
          No changelog events found for this project.
        </p>
      </div>
    </div>
    """
  end

  @doc """
  Renders a creation event for a project.
  """
  attr :event, :map, required: true, doc: "The creation event to display"

  def creation_event(assigns) do
    ~H"""
    <div class="border-l-4 border-green-500 pl-4 py-2">
      <div class="flex justify-between">
        <h4 class="font-medium text-green-700">Project Created</h4>
        <span class="text-gray-500 text-sm">
          {format_datetime(@event.recorded_at)}
        </span>
      </div>
      <div class="mt-2 text-sm">
        <p :if={@event.user}>Created by {@event.user.email}</p>
        <p :if={!@event.user}>Created by system</p>
      </div>
      <div class="mt-2">
        {raw(Patch.format_patch(%{patch: @event.patch}))}
      </div>
    </div>
    """
  end

  @doc """
  Renders a hiding event for a project.
  """
  attr :event, :map, required: true, doc: "The hiding event to display"

  def hiding_event(assigns) do
    ~H"""
    <div class="border-l-4 border-yellow-500 pl-4 py-2">
      <div class="flex justify-between">
        <h4 class="font-medium text-yellow-700">Project Hidden</h4>
        <span class="text-gray-500 text-sm">
          {format_datetime(@event.recorded_at)}
        </span>
      </div>
      <div class="mt-2 text-sm">
        <p :if={@event.user}>Hidden by {@event.user.email}</p>
        <p :if={!@event.user}>Hidden by system</p>
      </div>
      <div :if={@event.patch["hidden_reason"]} class="mt-2">
        <strong>Reason:</strong>
        {format_change_value(@event.patch["hidden_reason"])}
      </div>
    </div>
    """
  end

  @doc """
  Renders the main changelog list with search, pagination, and entries grouped by date.
  """
  attr :loading, :boolean, required: true, doc: "Whether data is currently loading"
  attr :changelog_entries, :list, required: true, doc: "List of changelog entries grouped by date"
  attr :search_term, :string, required: true, doc: "Current search term"
  attr :page, :integer, required: true, doc: "Current page number"
  attr :total_pages, :integer, required: true, doc: "Total number of pages"
  attr :total_dates, :integer, required: true, doc: "Total number of dates with changes"

  def changelog_list(assigns) do
    ~H"""
    <div class="bg-white shadow rounded-lg p-6">
      <div class="mb-6">
        <h3 class="text-lg font-semibold mb-4">Project Changelog</h3>

        <.search_form search_term={@search_term} />
      </div>

      <.loading_spinner :if={@loading} />

      <div :if={!@loading}>
        <.empty_state :if={Enum.empty?(@changelog_entries)} />

        <div :if={!Enum.empty?(@changelog_entries)}>
          <div class="space-y-8">
            <.changelog_entry :for={entry <- @changelog_entries} entry={entry} />
          </div>

          <.pagination page={@page} total_pages={@total_pages} total_dates={@total_dates} />
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
    <form phx-submit="search" class="mb-4">
      <div class="flex">
        <div class="relative flex-grow">
          <input
            type="text"
            name="search[term]"
            value={@search_term}
            placeholder="Search by project name or ticker..."
            class="w-full px-4 py-2 border border-gray-300 rounded-l-md focus:outline-none focus:ring-2 focus:ring-blue-500"
          />
        </div>
        <button
          type="submit"
          class="px-4 py-2 bg-blue-500 text-white rounded-r-md hover:bg-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-500"
        >
          Search
        </button>
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
      <div class="animate-spin rounded-full h-10 w-10 border-b-2 border-blue-500"></div>
    </div>
    """
  end

  @doc """
  Renders an empty state message when no changelog entries are found.
  """
  def empty_state(assigns) do
    ~H"""
    <div class="text-center py-10">
      <p class="text-gray-500">No changelog entries found.</p>
    </div>
    """
  end

  @doc """
  Renders a single changelog entry for a specific date.
  """
  attr :entry, :map,
    required: true,
    doc: "The changelog entry containing created and hidden projects for a date"

  def changelog_entry(assigns) do
    ~H"""
    <div class="border-b pb-6 last:border-b-0">
      <h3 class="text-xl font-semibold mb-4 text-gray-800">
        {format_date(@entry.date)}
      </h3>

      <.created_projects_section
        :if={not Enum.empty?(@entry.created_projects)}
        created_projects={@entry.created_projects}
      />

      <.hidden_projects_section
        :if={not Enum.empty?(@entry.hidden_projects)}
        hidden_projects={@entry.hidden_projects}
      />
    </div>
    """
  end

  @doc """
  Renders the section for created projects.
  """
  attr :created_projects, :list,
    required: true,
    doc: "List of projects created on a specific date"

  def created_projects_section(assigns) do
    ~H"""
    <div class="mb-6">
      <h4 class="text-md font-medium text-green-700 mb-3">
        Projects Created ({length(@created_projects)})
      </h4>
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        <.project_card
          :for={%{project: project, event: event} <- @created_projects}
          project={project}
          event={event}
          type={:created}
        />
      </div>
    </div>
    """
  end

  @doc """
  Renders the section for hidden projects.
  """
  attr :hidden_projects, :list, required: true, doc: "List of projects hidden on a specific date"

  def hidden_projects_section(assigns) do
    ~H"""
    <div>
      <h4 class="text-md font-medium text-yellow-700 mb-3">
        Projects Hidden ({length(@hidden_projects)})
      </h4>
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        <.project_card
          :for={%{project: project, event: event, reason: reason} <- @hidden_projects}
          project={project}
          event={event}
          type={:hidden}
          reason={reason}
        />
      </div>
    </div>
    """
  end

  @doc """
  Renders a card for a project with its details and event information.
  """
  attr :project, :map, required: true, doc: "The project to display"
  attr :event, :map, required: true, doc: "The event associated with the project"
  attr :type, :atom, required: true, doc: "The type of event (:created or :hidden)"
  attr :reason, :string, default: nil, doc: "The reason for hiding (only for hidden projects)"

  def project_card(assigns) do
    ~H"""
    <div class="border rounded-lg p-4 hover:shadow-md transition-shadow">
      <div class="flex items-center mb-2">
        <img
          :if={@project.logo_url}
          src={@project.logo_url}
          alt={@project.name}
          class="w-8 h-8 mr-3 rounded-full"
        />
        <div>
          <h5 class="font-medium">{@project.name}</h5>
          <p class="text-sm text-gray-500">{@project.ticker}</p>
          <p class="text-xs text-gray-400">{@project.slug}</p>
        </div>
      </div>

      <div :if={@reason && @type == :hidden} class="text-sm mt-2">
        <span class="font-medium">Reason:</span> {@reason}
      </div>

      <div class="text-xs text-gray-500 mt-2">
        <span :if={@event.user}>
          {if @type == :created, do: "Created", else: "Hidden"} by {@event.user.email}
        </span>
        <span :if={!@event.user}>
          {if @type == :created, do: "Created", else: "Hidden"} by system
        </span>
        at {format_time(@event.recorded_at)}
      </div>

      <div class="mt-2">
        <.link
          href={"https://app.santiment.net/charts?slug=#{@project.slug}&metrics=price_usd"}
          target="_blank"
          class="text-blue-600 hover:text-blue-900 text-sm"
        >
          Visit Page
        </.link>
      </div>
    </div>
    """
  end

  @doc """
  Renders the pagination controls.
  """
  attr :page, :integer, required: true, doc: "Current page number"
  attr :total_pages, :integer, required: true, doc: "Total number of pages"
  attr :total_dates, :integer, required: true, doc: "Total number of dates with changes"

  def pagination(assigns) do
    page_range = max(1, assigns.page - 2)..min(assigns.total_pages, assigns.page + 2)
    assigns = assign(assigns, :page_range, page_range)

    ~H"""
    <div class="mt-8 flex justify-between items-center">
      <div class="text-sm text-gray-700">
        Showing page {@page} of {@total_pages} (Total: {@total_dates} days with changes)
      </div>
      <div class="flex space-x-2">
        <button
          :if={@page > 1}
          phx-click="change_page"
          phx-value-page={@page - 1}
          class="px-3 py-1 bg-gray-200 text-gray-700 rounded hover:bg-gray-300"
        >
          Previous
        </button>

        <button
          :for={page_num <- @page_range}
          phx-click="change_page"
          phx-value-page={page_num}
          class={"px-3 py-1 rounded #{if page_num == @page, do: "bg-blue-500 text-white", else: "bg-gray-200 text-gray-700 hover:bg-gray-300"}"}
        >
          {page_num}
        </button>

        <button
          :if={@page < @total_pages}
          phx-click="change_page"
          phx-value-page={@page + 1}
          class="px-3 py-1 bg-gray-200 text-gray-700 rounded hover:bg-gray-300"
        >
          Next
        </button>
      </div>
    </div>
    """
  end

  # Helper functions
  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y %H:%M:%S")
  end

  defp format_date(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> Calendar.strftime(date, "%B %d, %Y")
      _ -> date_string
    end
  end

  defp format_time(datetime) do
    Calendar.strftime(datetime, "%H:%M:%S")
  end

  defp format_change_value({:changed, {:primitive_change, _old_val, new_val}}) do
    inspect(new_val)
  end

  defp format_change_value(value), do: inspect(value)

  defp calculate_total_pages(total_count) do
    ceil(total_count / @dates_per_page)
  end
end
