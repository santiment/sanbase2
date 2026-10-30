defmodule SanbaseWeb.Admin.PriceRescrapesLive do
  @moduledoc ~s"""
  Schedule coinmarketcap price rescrapes for one, many or all projects and
  follow their progress. Runs next to the generic admin page for
  `schedule_rescrape_prices`, which stays as it is.
  """
  use SanbaseWeb, :live_view

  import Sanbase.Utils.DateTime, only: [rough_duration_since: 1]

  alias Sanbase.Admin.Permissions
  alias Sanbase.ExternalServices.Coinmarketcap.ScheduleRescrapePrice
  alias Sanbase.Mix.Helper.ScheduleRescrapeHelpers

  @refresh_interval_ms 5_000
  @list_limit 200
  @status_filters ~w(active running pending finished failed cancelled all)
  @schedule_types %{from: :naive_datetime, to: :naive_datetime, priority: :string}
  @no_permission "You need the Admin Panel Editor role to do this."

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(@refresh_interval_ms, :refresh)

    {:ok,
     socket
     |> assign(
       page_title: "Price Rescrapes",
       can_edit?: Permissions.can?(:edit, roles: socket.assigns.current_user_role_names),
       status_filter: "active",
       search: "",
       suggestions: [],
       selected_projects: [],
       all_projects?: false,
       scheduling?: false,
       scheduled_slugs: []
     )
     |> assign_schedule_form(%{"priority" => "normal"})
     |> load_rescrapes()}
  end

  @impl true
  def handle_event("search_projects", %{"project_search" => search}, socket) do
    suggestions =
      if String.trim(search) == "",
        do: [],
        else: ScheduleRescrapePrice.search_projects(String.trim(search), 8)

    {:noreply, assign(socket, :suggestions, suggestions)}
  end

  # Enter in the search box adds all the slugs in it, so a list of slugs can be pasted
  def handle_event("add_projects", %{"project_search" => search}, socket) do
    slugs = String.split(search, [",", " ", "\n", "\t"], trim: true)
    {:noreply, add_projects(socket, slugs)}
  end

  def handle_event("add_project", %{"slug" => slug}, socket) do
    {:noreply, add_projects(socket, [slug])}
  end

  def handle_event("remove_project", %{"slug" => slug}, socket) do
    selected = Enum.reject(socket.assigns.selected_projects, &(&1.slug == slug))
    {:noreply, assign(socket, :selected_projects, selected)}
  end

  def handle_event("toggle_all_projects", _params, socket) do
    {:noreply, assign(socket, :all_projects?, not socket.assigns.all_projects?)}
  end

  def handle_event("preset", %{"days" => days}, socket) do
    to = %{NaiveDateTime.utc_now() | second: 0, microsecond: {0, 0}}
    from = NaiveDateTime.add(to, -String.to_integer(days) * 86_400)
    params = Map.merge(socket.assigns.schedule_params, %{"from" => from, "to" => to})

    {:noreply, assign_schedule_form(socket, params)}
  end

  def handle_event("validate_schedule", %{"rescrape" => params}, socket) do
    {:noreply, assign_schedule_form(socket, params, :validate)}
  end

  def handle_event("schedule", %{"rescrape" => params}, socket) do
    changeset = schedule_changeset(params)
    %{can_edit?: can_edit?, all_projects?: all?, selected_projects: selected} = socket.assigns

    cond do
      not can_edit? ->
        {:noreply, put_flash(socket, :error, @no_permission)}

      socket.assigns.scheduling? ->
        {:noreply, socket}

      not changeset.valid? ->
        {:noreply, assign_schedule_form(socket, params, :validate)}

      not all? and selected == [] ->
        {:noreply, put_flash(socket, :error, "Pick at least one project")}

      true ->
        {:noreply, start_scheduling(socket, changeset, if(all?, do: nil, else: selected))}
    end
  end

  def handle_event("filter_status", %{"status" => status}, socket)
      when status in @status_filters do
    {:noreply, socket |> assign(:status_filter, status) |> load_rescrapes()}
  end

  def handle_event("filter_search", %{"search" => search}, socket) do
    {:noreply, socket |> assign(:search, search) |> load_rescrapes()}
  end

  def handle_event("set_priority", %{"rescrape_id" => id, "priority" => priority}, socket) do
    with_rescrape(socket, id, &ScheduleRescrapePrice.update_priority(&1, priority))
  end

  def handle_event("cancel", %{"id" => id}, socket) do
    with_rescrape(socket, id, &ScheduleRescrapePrice.cancel/1)
  end

  def handle_event("resume", %{"id" => id}, socket) do
    with_rescrape(socket, id, &ScheduleRescrapePrice.resume/1)
  end

  @impl true
  def handle_async(:schedule, {:ok, {total, errors}}, socket) do
    # Unpick the scheduled projects. The failed ones and the ones picked meanwhile stay.
    failed = MapSet.new(errors, &elem(&1, 0))
    scheduled = MapSet.new(socket.assigns.scheduled_slugs) |> MapSet.difference(failed)

    socket =
      socket
      |> assign(
        scheduling?: false,
        all_projects?: false,
        selected_projects: Enum.reject(socket.assigns.selected_projects, &(&1.slug in scheduled))
      )
      |> put_flash(:info, "Scheduled #{total - length(errors)} rescrape(s)")
      |> load_rescrapes()

    socket =
      if errors == [],
        do: socket,
        else:
          put_flash(
            socket,
            :error,
            "Skipped: " <> Enum.map_join(errors, "; ", &"#{elem(&1, 0)} #{elem(&1, 1)}")
          )

    {:noreply, socket}
  end

  def handle_async(:schedule, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:scheduling?, false)
     |> put_flash(:error, "Scheduling failed: #{inspect(reason, limit: 20)}")}
  end

  @impl true
  def handle_info(:refresh, socket), do: {:noreply, load_rescrapes(socket)}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col w-full px-4 py-6 gap-6">
      <div class="flex flex-wrap items-center justify-between gap-4">
        <div>
          <h1 class="text-2xl font-bold">{@page_title}</h1>
          <p class="text-sm text-base-content/60">
            Rescrapes run in the background, the highest priority first, and do not hold back
            the regular scraper. Updated every 5 seconds.
          </p>
        </div>
        <.link
          href={~p"/admin/generic?resource=schedule_rescrape_prices"}
          class="btn btn-ghost btn-sm"
        >
          Generic admin view
        </.link>
      </div>

      <div id="status-tiles" class="flex flex-wrap gap-2">
        <button
          :for={status <- ~w(active running pending finished failed cancelled all)}
          id={"status-tile-#{status}"}
          type="button"
          phx-click="filter_status"
          phx-value-status={status}
          class={["btn btn-sm", if(@status_filter == status, do: "btn-primary", else: "btn-ghost")]}
        >
          {status} <span class="badge badge-sm">{status_count(@counts, status)}</span>
        </button>
      </div>

      <.schedule_form :if={@can_edit?} {assigns} />
      <div :if={not @can_edit?} id="read-only-notice" class="alert alert-soft text-sm">
        Scheduling and changing rescrapes needs the Admin Panel Editor role.
      </div>

      <div class="flex flex-col gap-2">
        <div class="flex items-center gap-3">
          <.form for={%{}} id="rescrapes-filter-form" phx-change="filter_search" class="w-72">
            <input
              type="text"
              name="search"
              value={@search}
              placeholder="Filter by project slug or name"
              phx-debounce="300"
              class="input input-sm w-full"
            />
          </.form>
          <span :if={@truncated?} id="rescrapes-truncated" class="text-xs text-warning">
            Showing the first {@list_limit}, filter to find the rest
          </span>
        </div>

        <div class="rounded-box border border-base-300 overflow-x-auto">
          <table class="table table-sm">
            <thead>
              <tr>
                <th>Project</th>
                <th>Interval (UTC)</th>
                <th>Status</th>
                <th class="min-w-56">Progress</th>
                <th>Priority</th>
                <th>Created</th>
                <th><span class="sr-only">Actions</span></th>
              </tr>
            </thead>
            <tbody id="rescrapes" phx-update="stream">
              <tr id="rescrapes-empty" class="hidden only:table-row">
                <td colspan="7" class="text-center text-base-content/50 py-6">No rescrapes</td>
              </tr>
              <tr :for={{dom_id, srp} <- @streams.rescrapes} id={dom_id} class="align-top">
                <.rescrape_row srp={srp} now={@now} can_edit?={@can_edit?} />
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end

  defp schedule_form(assigns) do
    ~H"""
    <section
      id="schedule-card"
      class="rounded-box border border-base-300 p-4 grid lg:grid-cols-2 gap-6"
    >
      <div class="flex flex-col gap-2">
        <label class="label gap-2 text-sm">
          <input
            id="all-projects-toggle"
            type="checkbox"
            class="toggle toggle-sm"
            checked={@all_projects?}
            phx-click="toggle_all_projects"
          /> All coinmarketcap projects
        </label>

        <.form
          :if={not @all_projects?}
          for={%{}}
          id="project-search-form"
          phx-change="search_projects"
          phx-submit="add_projects"
          class="relative"
        >
          <input
            type="text"
            name="project_search"
            placeholder="Search by slug, name or ticker, or paste slugs and press Enter"
            autocomplete="off"
            phx-debounce="200"
            class="input w-full"
          />
          <ul
            :if={@suggestions != []}
            class="absolute z-20 mt-1 w-full menu rounded-box border border-base-300 bg-base-100 shadow-lg"
          >
            <li :for={p <- @suggestions}>
              <button
                type="button"
                id={"suggestion-#{p.slug}"}
                phx-click="add_project"
                phx-value-slug={p.slug}
              >
                {p.name} <span class="text-base-content/50">{p.slug}</span>
              </button>
            </li>
          </ul>
        </.form>

        <div :if={not @all_projects?} id="selected-projects" class="flex flex-wrap gap-2">
          <span
            :for={p <- @selected_projects}
            id={"selected-#{p.slug}"}
            class="badge badge-primary badge-soft gap-1"
          >
            {p.slug}
            <button
              type="button"
              phx-click="remove_project"
              phx-value-slug={p.slug}
              aria-label={"Remove #{p.slug}"}
            >
              <.icon name="hero-x-mark" class="size-3" />
            </button>
          </span>
        </div>
      </div>

      <.form
        for={@schedule_form}
        id="schedule-form"
        phx-change="validate_schedule"
        phx-submit="schedule"
      >
        <div class="flex gap-1 mb-2">
          <button
            :for={{days, label} <- [{"1", "24h"}, {"7", "7d"}, {"30", "30d"}, {"365", "1y"}]}
            type="button"
            phx-click="preset"
            phx-value-days={days}
            class="btn btn-xs btn-outline"
          >
            Last {label}
          </button>
        </div>
        <div class="grid grid-cols-3 gap-3">
          <.input field={@schedule_form[:from]} type="datetime-local" label="From (UTC)" />
          <.input field={@schedule_form[:to]} type="datetime-local" label="To (UTC)" />
          <.input
            field={@schedule_form[:priority]}
            type="select"
            label="Priority"
            options={~w(high normal low)}
          />
        </div>
        <button
          id="schedule-submit"
          type="submit"
          class="btn btn-primary"
          disabled={@scheduling?}
          data-confirm={@all_projects? && "Schedule a rescrape for every coinmarketcap project?"}
        >
          {if @scheduling?, do: "Scheduling…", else: "Schedule"}
        </button>
      </.form>
    </section>
    """
  end

  defp rescrape_row(assigns) do
    assigns =
      assign(assigns,
        progress: ScheduleRescrapePrice.progress(assigns.srp, assigns.now),
        active?: ScheduleRescrapePrice.active?(assigns.srp)
      )

    ~H"""
    <td>
      <.link href={~p"/admin/generic/#{@srp.project_id}?resource=projects"} class="link link-hover">
        {@srp.project.slug}
      </.link>
    </td>
    <td class="text-xs whitespace-nowrap">
      {format_datetime(@srp.from)}<br />→ {format_datetime(@srp.to)}
    </td>
    <td>
      <span class={["badge badge-sm", status_badge_class(@srp.status)]}>{@srp.status}</span>
      <div class="text-xs text-base-content/50">{activity_text(@srp, @now)}</div>
    </td>
    <td>
      <progress class="progress progress-primary w-full" value={round(@progress * 100)} max="100"></progress>
      <div class="text-xs text-base-content/60">
        {round(@progress * 100)}%
        <span :if={@srp.progress_datetime}>· at {format_datetime(@srp.progress_datetime)}</span>
      </div>
      <div
        :if={@srp.last_error}
        class="text-xs text-error line-clamp-2 max-w-sm"
        title={@srp.last_error}
      >
        {@srp.last_error}
      </div>
    </td>
    <td>
      <.form
        :if={@can_edit? and @active?}
        for={%{}}
        id={"priority-form-#{@srp.id}"}
        phx-change="set_priority"
      >
        <input type="hidden" name="rescrape_id" value={@srp.id} />
        <select name="priority" class="select select-xs w-24">
          {Phoenix.HTML.Form.options_for_select(~w(high normal low), to_string(@srp.priority))}
        </select>
      </.form>
      <span :if={not (@can_edit? and @active?)}>{@srp.priority}</span>
    </td>
    <td class="text-xs whitespace-nowrap">{rough_duration_since(@srp.inserted_at)} ago</td>
    <td class="text-right whitespace-nowrap">
      <button
        :if={@can_edit? and @active?}
        id={"cancel-#{@srp.id}"}
        type="button"
        phx-click="cancel"
        phx-value-id={@srp.id}
        data-confirm={"Cancel the rescrape of #{@srp.project.slug}?"}
        class="btn btn-ghost btn-xs text-error"
      >
        Cancel
      </button>
      <button
        :if={@can_edit? and @srp.status in [:failed, :cancelled]}
        id={"resume-#{@srp.id}"}
        type="button"
        phx-click="resume"
        phx-value-id={@srp.id}
        class="btn btn-ghost btn-xs"
      >
        Resume
      </button>
    </td>
    """
  end

  defp load_rescrapes(socket) do
    status =
      if socket.assigns.status_filter == "all",
        do: nil,
        else: String.to_existing_atom(socket.assigns.status_filter)

    rescrapes =
      ScheduleRescrapePrice.list(
        status: status,
        search: String.trim(socket.assigns.search),
        limit: @list_limit
      )

    socket
    |> assign(
      now: NaiveDateTime.utc_now(),
      counts: ScheduleRescrapePrice.status_counts(),
      list_limit: @list_limit,
      truncated?: length(rescrapes) == @list_limit
    )
    |> stream(:rescrapes, rescrapes, reset: true)
  end

  # Apply `fun` to the rescrape and reload the list
  defp with_rescrape(socket, id, fun) do
    socket =
      with true <- socket.assigns.can_edit? || {:error, @no_permission},
           {id, ""} <- Integer.parse(id),
           {:ok, srp} <- ScheduleRescrapePrice.by_id(id),
           {:ok, _} <- fun.(srp) do
        put_flash(socket, :info, "Updated the rescrape of #{srp.project.slug}")
      else
        {:error, :not_active} ->
          put_flash(socket, :error, "The rescrape is no longer active")

        {:error, %Ecto.Changeset{} = changeset} ->
          put_flash(socket, :error, format_errors(changeset))

        {:error, error} ->
          put_flash(socket, :error, error)

        _ ->
          put_flash(socket, :error, "Invalid rescrape id")
      end

    {:noreply, load_rescrapes(socket)}
  end

  defp add_projects(socket, slugs) do
    projects = ScheduleRescrapePrice.projects_by_slugs(slugs)
    selected = Enum.uniq_by(socket.assigns.selected_projects ++ projects, & &1.slug)
    unknown = slugs -- Enum.map(projects, & &1.slug)

    socket = assign(socket, selected_projects: selected, suggestions: [])

    if unknown == [],
      do: socket,
      else:
        put_flash(socket, :error, "Not scraped from coinmarketcap: #{Enum.join(unknown, ", ")}")
  end

  # `projects` is nil when scheduling all the coinmarketcap projects
  defp start_scheduling(socket, changeset, projects) do
    %{from: from, to: to, priority: priority} = Ecto.Changeset.apply_changes(changeset)
    priority = String.to_existing_atom(priority)

    socket
    |> assign(scheduling?: true, scheduled_slugs: Enum.map(projects || [], & &1.slug))
    |> start_async(:schedule, fn -> schedule(projects, from, to, priority) end)
  end

  # Runs in a task, so scheduling all the projects does not block the page
  defp schedule(projects, from, to, priority) do
    projects =
      projects || Sanbase.Project.List.projects_with_source("coinmarketcap", include_hidden: true)

    errors =
      ScheduleRescrapeHelpers.run(from, to, projects: projects, priority: priority)
      |> Enum.map(fn {slug, errors} -> {slug, format_errors(errors)} end)

    {length(projects), errors}
  end

  defp assign_schedule_form(socket, params, action \\ nil) do
    form = params |> schedule_changeset() |> to_form(as: :rescrape, action: action)
    assign(socket, schedule_params: params, schedule_form: form)
  end

  defp schedule_changeset(params) do
    changeset =
      {%{}, @schedule_types}
      |> Ecto.Changeset.cast(params, Map.keys(@schedule_types))
      |> Ecto.Changeset.validate_required([:from, :to, :priority])
      |> Ecto.Changeset.validate_inclusion(:priority, ~w(high normal low))

    from = Ecto.Changeset.get_field(changeset, :from)
    to = Ecto.Changeset.get_field(changeset, :to)

    if from && to && NaiveDateTime.compare(from, to) != :lt,
      do: Ecto.Changeset.add_error(changeset, :to, "must be after `from`"),
      else: changeset
  end

  defp format_errors(%Ecto.Changeset{} = changeset),
    do: changeset |> Sanbase.Utils.ErrorHandling.changeset_errors() |> format_errors()

  defp format_errors(errors) when is_map(errors) do
    Enum.map_join(errors, "; ", fn
      {:project_id, messages} -> Enum.join(messages, ", ")
      {field, messages} -> "#{field} #{Enum.join(messages, ", ")}"
    end)
  end

  defp status_count(counts, "all"), do: counts |> Map.values() |> Enum.sum()

  defp status_count(counts, "active"),
    do: Map.get(counts, :running, 0) + Map.get(counts, :pending, 0)

  defp status_count(counts, status), do: Map.get(counts, String.to_existing_atom(status), 0)

  defp status_badge_class(:running), do: "badge-success"
  defp status_badge_class(:pending), do: "badge-warning"
  defp status_badge_class(:failed), do: "badge-error"
  defp status_badge_class(_status), do: "badge-ghost"

  # A running rescrape with an error is waiting to retry the failed day
  defp activity_text(%{status: :pending}, _now), do: "waiting for a free slot"

  defp activity_text(%{status: :running, last_error: error}, _now) when is_binary(error),
    do: "retrying"

  defp activity_text(%{status: :running, updated_at: updated_at}, _now),
    do: "last progress #{rough_duration_since(updated_at)} ago"

  defp activity_text(_srp, _now), do: nil

  defp format_datetime(%NaiveDateTime{} = ndt), do: Calendar.strftime(ndt, "%Y-%m-%d %H:%M")
end
