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
      <.link navigate={~p"/admin/project_changelog"} class="link link-primary">
        &larr; Back to changelog
      </.link>
    </div>

    <div class="card bg-base-100 border border-base-300 shadow p-6 mb-6">
      <div class="flex items-center mb-4">
        <img
          :if={@project.logo_url}
          src={@project.logo_url}
          alt={@project.name}
          class="w-12 h-12 mr-4 rounded-full"
        />
        <div>
          <h2 class="text-xl font-bold">{@project.name}</h2>
          <p class="text-base-content/60">{@project.ticker}</p>
          <p class="text-base-content/50 text-sm">{@project.slug}</p>
        </div>
      </div>

      <p :if={@project.description} class="mb-4">{@project.description}</p>

      <.link href={Project.sanbase_link(@project)} target="_blank" class="link link-primary">
        View project page
      </.link>
    </div>

    <div class="card bg-base-100 border border-base-300 shadow p-6">
      <h3 class="text-lg font-semibold mb-4">Changelog</h3>

      <div class="space-y-6">
        <.creation_event :if={@events.creation_event} event={@events.creation_event} />

        <.hiding_event :for={event <- @events.hiding_events} event={event} />

        <p
          :if={@events.creation_event == nil and @events.hiding_events == []}
          class="text-base-content/50 italic"
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
    <div class="border-l-4 border-success pl-4 py-2">
      <div class="flex justify-between">
        <h4 class="font-medium text-success">Project Created</h4>
        <span class="text-base-content/50 text-sm">
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
    <div class="border-l-4 border-warning pl-4 py-2">
      <div class="flex justify-between">
        <h4 class="font-medium text-warning">Project Hidden</h4>
        <span class="text-base-content/50 text-sm">
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
    <div class="card bg-base-100 border border-base-300 shadow p-6">
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
      <div class="join w-full">
        <input
          type="text"
          name="search[term]"
          value={@search_term}
          placeholder="Search by project name or ticker..."
          class="input join-item flex-1"
        />
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
  Renders an empty state message when no changelog entries are found.
  """
  def empty_state(assigns) do
    ~H"""
    <div class="text-center py-10">
      <p class="text-base-content/50">No changelog entries found.</p>
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
    <div class="border-b border-base-300 pb-6 last:border-b-0">
      <h3 class="text-xl font-semibold mb-4">
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
      <div class="flex items-center mb-3">
        <span class="badge badge-sm badge-success badge-soft">
          Projects Created ({length(@created_projects)})
        </span>
      </div>
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
      <div class="flex items-center mb-3">
        <span class="badge badge-sm badge-warning badge-soft">
          Projects Hidden ({length(@hidden_projects)})
        </span>
      </div>
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
    <div class="card bg-base-100 border border-base-300 p-4 hover:shadow-md transition-shadow">
      <div class="flex items-center mb-2">
        <img
          :if={@project.logo_url}
          src={@project.logo_url}
          alt={@project.name}
          class="w-8 h-8 mr-3 rounded-full"
        />
        <div>
          <h5 class="font-medium">{@project.name}</h5>
          <p class="text-sm text-base-content/60">{@project.ticker}</p>
          <p class="text-xs text-base-content/40">{@project.slug}</p>
        </div>
      </div>

      <div :if={@reason && @type == :hidden} class="text-sm mt-2">
        <span class="font-medium">Reason:</span> {@reason}
      </div>

      <div class="text-xs text-base-content/50 mt-2">
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
          class="link link-primary text-sm"
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
      <div class="text-sm text-base-content/70">
        Showing page {@page} of {@total_pages} (Total: {@total_dates} days with changes)
      </div>
      <div class="join">
        <button
          :if={@page > 1}
          phx-click="change_page"
          phx-value-page={@page - 1}
          class="btn btn-sm btn-soft join-item"
        >
          Previous
        </button>

        <button
          :for={page_num <- @page_range}
          phx-click="change_page"
          phx-value-page={page_num}
          class={[
            "btn btn-sm join-item",
            if(page_num == @page, do: "btn-primary", else: "btn-soft")
          ]}
        >
          {page_num}
        </button>

        <button
          :if={@page < @total_pages}
          phx-click="change_page"
          phx-value-page={@page + 1}
          class="btn btn-sm btn-soft join-item"
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
