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
  @suggestions_limit 8
  @status_filters ~w(active running pending finished failed cancelled all)
  @schedule_types %{from: :naive_datetime, to: :naive_datetime, priority: :string}
  @presets [
    {"1", "24h"},
    {"7", "7 days"},
    {"30", "30 days"},
    {"90", "90 days"},
    {"365", "1 year"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(@refresh_interval_ms, :refresh)

    {:ok,
     socket
     |> assign(
       page_title: "Price Rescrapes",
       can_edit?: Permissions.can?(:edit, roles: socket.assigns.current_user_role_names),
       presets: @presets,
       status_filter: "active",
       search: "",
       project_search: "",
       suggestions: [],
       selected_projects: [],
       unknown_slugs: [],
       all_projects?: false,
       scheduling?: false,
       schedule_result: nil
     )
     |> assign_schedule_form(%{"priority" => "normal"})
     |> load_rescrapes()}
  end

  # ─── Events: scheduling ──────────────────────────────────────────────────

  @impl true
  def handle_event("search_projects", %{"project_search" => search}, socket) do
    suggestions =
      case String.trim(search) do
        "" -> []
        search -> ScheduleRescrapePrice.search_projects(search, @suggestions_limit)
      end

    {:noreply, assign(socket, project_search: search, suggestions: suggestions)}
  end

  # Enter in the search box adds all the slugs in it, so a list of slugs can be pasted
  def handle_event("add_projects", %{"project_search" => search}, socket) do
    slugs = search |> String.split([",", " ", "\n", "\t"], trim: true) |> Enum.uniq()
    projects = ScheduleRescrapePrice.projects_by_slugs(slugs)
    found = MapSet.new(projects, & &1.slug)

    {:noreply,
     socket
     |> add_selected_projects(projects)
     |> assign(
       project_search: "",
       suggestions: [],
       unknown_slugs: Enum.reject(slugs, &MapSet.member?(found, &1))
     )}
  end

  def handle_event("add_project", %{"slug" => slug}, socket) do
    projects = ScheduleRescrapePrice.projects_by_slugs([slug])

    {:noreply,
     socket
     |> add_selected_projects(projects)
     |> assign(project_search: "", suggestions: [], unknown_slugs: [])}
  end

  def handle_event("remove_project", %{"slug" => slug}, socket) do
    selected = Enum.reject(socket.assigns.selected_projects, &(&1.slug == slug))
    {:noreply, assign(socket, :selected_projects, selected)}
  end

  def handle_event("clear_projects", _params, socket) do
    {:noreply, assign(socket, selected_projects: [], unknown_slugs: [])}
  end

  def handle_event("toggle_all_projects", _params, socket) do
    {:noreply, assign(socket, :all_projects?, not socket.assigns.all_projects?)}
  end

  def handle_event("preset", %{"days" => days}, socket) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    to = %{now | second: 0}
    from = NaiveDateTime.add(to, -String.to_integer(days) * 86_400)

    params =
      socket.assigns.schedule_params
      |> Map.put("from", datetime_local(from))
      |> Map.put("to", datetime_local(to))

    {:noreply, assign_schedule_form(socket, params)}
  end

  def handle_event("validate_schedule", %{"rescrape" => params}, socket) do
    {:noreply, assign_schedule_form(socket, params, :validate)}
  end

  def handle_event("schedule", %{"rescrape" => params}, socket) do
    changeset = schedule_changeset(params)

    cond do
      not socket.assigns.can_edit? ->
        {:noreply, put_flash(socket, :error, "You need the Admin Panel Editor role to do this.")}

      not changeset.valid? ->
        {:noreply, assign_schedule_form(socket, params, :validate)}

      not socket.assigns.all_projects? and socket.assigns.selected_projects == [] ->
        {:noreply, put_flash(socket, :error, "Pick at least one project")}

      true ->
        %{from: from, to: to, priority: priority} = Ecto.Changeset.apply_changes(changeset)
        priority = String.to_existing_atom(priority)

        projects =
          if socket.assigns.all_projects?, do: nil, else: socket.assigns.selected_projects

        {:noreply,
         socket
         |> assign(scheduling?: true, schedule_result: nil)
         |> start_async(:schedule, fn -> schedule(projects, from, to, priority) end)}
    end
  end

  def handle_event("dismiss_result", _params, socket) do
    {:noreply, assign(socket, :schedule_result, nil)}
  end

  # ─── Events: rescrapes ───────────────────────────────────────────────────

  def handle_event("filter_status", %{"status" => status}, socket)
      when status in @status_filters do
    {:noreply, socket |> assign(:status_filter, status) |> load_rescrapes()}
  end

  def handle_event("filter_search", %{"search" => search}, socket) do
    {:noreply, socket |> assign(:search, search) |> load_rescrapes()}
  end

  def handle_event("set_priority", %{"rescrape_id" => id, "priority" => priority}, socket) do
    with_rescrape(socket, id, fn srp ->
      case ScheduleRescrapePrice.update_priority(srp, priority) do
        {:ok, srp} -> {:info, "#{srp.project.slug}: priority set to #{srp.priority}"}
        {:error, changeset} -> {:error, errors_to_string(changeset)}
      end
    end)
  end

  def handle_event("cancel", %{"id" => id}, socket) do
    with_rescrape(socket, id, fn srp ->
      case ScheduleRescrapePrice.cancel(srp) do
        {:ok, _} -> {:info, "#{srp.project.slug}: rescrape cancelled"}
        {:error, :not_active} -> {:error, "#{srp.project.slug}: the rescrape is no longer active"}
      end
    end)
  end

  def handle_event("resume", %{"id" => id}, socket) do
    with_rescrape(socket, id, fn srp ->
      case ScheduleRescrapePrice.resume(srp) do
        {:ok, _} ->
          {:info, "#{srp.project.slug}: rescrape resumed"}

        {:error, %Ecto.Changeset{} = cs} ->
          {:error, "#{srp.project.slug}: #{errors_to_string(cs)}"}

        {:error, error} ->
          {:error, "#{srp.project.slug}: #{error}"}
      end
    end)
  end

  @impl true
  def handle_async(:schedule, {:ok, {total, errors}}, socket) do
    created = total - length(errors)

    selected =
      if errors == [] do
        []
      else
        failed = MapSet.new(errors, &elem(&1, 0))
        Enum.filter(socket.assigns.selected_projects, &MapSet.member?(failed, &1.slug))
      end

    {:noreply,
     socket
     |> assign(
       scheduling?: false,
       all_projects?: socket.assigns.all_projects? and errors != [],
       selected_projects: selected,
       schedule_result: %{created: created, errors: errors}
     )
     |> load_rescrapes()}
  end

  def handle_async(:schedule, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:scheduling?, false)
     |> put_flash(:error, "Scheduling failed: #{inspect(reason, limit: 20)}")
     |> load_rescrapes()}
  end

  @impl true
  def handle_info(:refresh, socket), do: {:noreply, load_rescrapes(socket)}

  # ─── Render ──────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col w-full px-4 py-6 gap-6 max-w-[1600px] mx-auto">
      <header class="flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 class="text-2xl font-bold">{@page_title}</h1>
          <p class="text-sm text-base-content/60 mt-1">
            Re-fetch coinmarketcap prices for a time range. Rescrapes run in the background,
            the highest priority first, with their own cursor and do not hold back the regular
            scraper.
          </p>
        </div>
        <div class="flex items-center gap-3 text-sm">
          <span class="flex items-center gap-2 text-base-content/60">
            <span class="relative flex size-2">
              <span class="absolute inline-flex size-full rounded-full bg-success opacity-60 animate-ping"></span>
              <span class="relative inline-flex size-2 rounded-full bg-success"></span>
            </span>
            Live · updated {Calendar.strftime(@now, "%H:%M:%S")} UTC
          </span>
          <.link
            href={~p"/admin/generic?resource=schedule_rescrape_prices"}
            class="btn btn-ghost btn-sm"
            id="legacy-admin-link"
          >
            <.icon name="hero-table-cells" class="size-4" /> Generic admin view
          </.link>
        </div>
      </header>

      <.status_tiles counts={@counts} status_filter={@status_filter} />

      <.schedule_card :if={@can_edit?} {assigns} />
      <div
        :if={not @can_edit?}
        id="read-only-notice"
        class="alert alert-soft text-sm"
      >
        <.icon name="hero-lock-closed" class="size-4" />
        You can follow the rescrapes. Scheduling and changing them needs the Admin Panel Editor role.
      </div>

      <.rescrapes_table {assigns} />
    </div>
    """
  end

  defp status_tiles(assigns) do
    assigns =
      assign(assigns, :tiles, [
        {"active", "Active", active_count(assigns.counts), "bg-info"},
        {"running", "Running", Map.get(assigns.counts, :running, 0), "bg-success"},
        {"pending", "Pending", Map.get(assigns.counts, :pending, 0), "bg-warning"},
        {"finished", "Finished", Map.get(assigns.counts, :finished, 0), "bg-base-content/40"},
        {"failed", "Failed", Map.get(assigns.counts, :failed, 0), "bg-error"},
        {"cancelled", "Cancelled", Map.get(assigns.counts, :cancelled, 0), "bg-base-content/20"},
        {"all", "All", assigns.counts |> Map.values() |> Enum.sum(), "bg-primary"}
      ])

    ~H"""
    <div id="status-tiles" class="grid grid-cols-2 sm:grid-cols-4 xl:grid-cols-7 gap-3">
      <button
        :for={{status, label, count, dot} <- @tiles}
        id={"status-tile-#{status}"}
        type="button"
        phx-click="filter_status"
        phx-value-status={status}
        class={[
          "group text-left rounded-xl border px-4 py-3 transition-all duration-150",
          "hover:-translate-y-0.5 hover:shadow-md cursor-pointer",
          if(@status_filter == status,
            do: "border-primary bg-primary/5 shadow-sm",
            else: "border-base-300 bg-base-100 hover:border-base-content/20"
          )
        ]}
      >
        <div class="flex items-center gap-2 text-xs uppercase tracking-wide text-base-content/60">
          <span class={["size-2 rounded-full", dot]}></span>
          {label}
        </div>
        <div class="text-2xl font-semibold tabular-nums mt-1">{count}</div>
      </button>
    </div>
    """
  end

  defp schedule_card(assigns) do
    ~H"""
    <section id="schedule-card" class="rounded-2xl border border-base-300 bg-base-100 shadow-sm">
      <div class="px-5 py-4 border-b border-base-300 flex items-center gap-2">
        <.icon name="hero-arrow-path" class="size-5 text-primary" />
        <h2 class="font-semibold">Schedule a rescrape</h2>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-5 gap-6 p-5">
        <%!-- Projects --%>
        <div class="lg:col-span-3 flex flex-col gap-3">
          <div class="flex items-center justify-between">
            <span class="text-sm font-medium">Projects</span>
            <label class="label cursor-pointer gap-2 text-sm">
              <input
                id="all-projects-toggle"
                type="checkbox"
                class="toggle toggle-sm toggle-primary"
                checked={@all_projects?}
                phx-click="toggle_all_projects"
              /> All coinmarketcap projects
            </label>
          </div>

          <div
            :if={@all_projects?}
            id="all-projects-notice"
            class="rounded-xl border border-warning/40 bg-warning/10 px-4 py-3 text-sm"
          >
            Every project scraped from coinmarketcap gets a rescrape. Projects that already have an
            active rescrape are skipped and listed after scheduling.
          </div>

          <div :if={not @all_projects?} class="flex flex-col gap-3">
            <.form
              for={%{}}
              id="project-search-form"
              phx-change="search_projects"
              phx-submit="add_projects"
              class="relative"
            >
              <div class="relative">
                <.icon
                  name="hero-magnifying-glass"
                  class="size-4 absolute left-3 top-1/2 -translate-y-1/2 text-base-content/40 z-10"
                />
                <input
                  id="project-search-input"
                  type="text"
                  name="project_search"
                  value={@project_search}
                  placeholder="Search by slug, name or ticker — or paste slugs and press Enter"
                  autocomplete="off"
                  phx-debounce="200"
                  class="input w-full pl-9"
                />
              </div>

              <ul
                :if={@suggestions != []}
                id="project-suggestions"
                class="absolute z-20 mt-1 w-full rounded-xl border border-base-300 bg-base-100 shadow-lg overflow-hidden"
              >
                <li :for={p <- @suggestions}>
                  <button
                    type="button"
                    id={"suggestion-#{p.slug}"}
                    phx-click="add_project"
                    phx-value-slug={p.slug}
                    class="w-full flex items-center justify-between gap-3 px-4 py-2 text-left text-sm hover:bg-base-200 transition-colors"
                  >
                    <span class="flex items-center gap-2 min-w-0">
                      <span class="font-medium truncate">{p.name}</span>
                      <span class="text-base-content/50 truncate">{p.slug}</span>
                      <span :if={p.ticker} class="badge badge-ghost badge-sm">{p.ticker}</span>
                    </span>
                    <span :if={p.rank} class="text-xs text-base-content/50 tabular-nums">
                      #{p.rank}
                    </span>
                  </button>
                </li>
              </ul>
            </.form>

            <div
              id="selected-projects"
              class="min-h-[3.5rem] rounded-xl border border-dashed border-base-300 p-3 flex flex-wrap gap-2 content-start"
            >
              <span
                :if={@selected_projects == []}
                class="text-sm text-base-content/40 self-center"
              >
                No projects picked yet
              </span>
              <span
                :for={p <- @selected_projects}
                id={"selected-#{p.slug}"}
                class="inline-flex items-center gap-1.5 rounded-full bg-primary/10 text-primary pl-3 pr-1 py-1 text-sm"
              >
                {p.slug}
                <button
                  type="button"
                  phx-click="remove_project"
                  phx-value-slug={p.slug}
                  class="rounded-full p-0.5 hover:bg-primary/20 transition-colors"
                  aria-label={"Remove #{p.slug}"}
                >
                  <.icon name="hero-x-mark" class="size-3.5" />
                </button>
              </span>
            </div>

            <div class="flex items-center justify-between text-xs text-base-content/60">
              <span>
                {length(@selected_projects)} selected
                <span :if={@unknown_slugs != []} id="unknown-slugs" class="text-error ml-2">
                  Not found or not scraped from coinmarketcap: {Enum.join(@unknown_slugs, ", ")}
                </span>
              </span>
              <button
                :if={@selected_projects != []}
                type="button"
                phx-click="clear_projects"
                class="link link-hover"
              >
                Clear
              </button>
            </div>
          </div>
        </div>

        <%!-- Interval and priority --%>
        <.form
          for={@schedule_form}
          id="schedule-form"
          phx-change="validate_schedule"
          phx-submit="schedule"
          class="lg:col-span-2 flex flex-col gap-1"
        >
          <div class="flex flex-wrap gap-1.5 mb-2">
            <span class="text-xs text-base-content/60 self-center mr-1">Last</span>
            <button
              :for={{days, label} <- @presets}
              type="button"
              id={"preset-#{days}"}
              phx-click="preset"
              phx-value-days={days}
              class="btn btn-xs btn-outline rounded-full"
            >
              {label}
            </button>
          </div>

          <div class="grid grid-cols-2 gap-3">
            <.input field={@schedule_form[:from]} type="datetime-local" label="From (UTC)" />
            <.input field={@schedule_form[:to]} type="datetime-local" label="To (UTC)" />
          </div>

          <.input
            field={@schedule_form[:priority]}
            type="select"
            label="Priority"
            options={[
              {"High — served before the regular scraper", "high"},
              {"Normal — shares the rate limit", "normal"},
              {"Low — only uses spare capacity", "low"}
            ]}
          />

          <button
            id="schedule-submit"
            type="submit"
            class="btn btn-primary mt-2 transition-transform active:scale-[0.98]"
            disabled={@scheduling?}
            data-confirm={@all_projects? && "Schedule a rescrape for every coinmarketcap project?"}
          >
            <span :if={@scheduling?} class="loading loading-spinner loading-sm"></span>
            <.icon :if={not @scheduling?} name="hero-play" class="size-4" />
            {schedule_button_text(@scheduling?, @all_projects?, length(@selected_projects))}
          </button>
        </.form>
      </div>

      <.schedule_result :if={@schedule_result} result={@schedule_result} />
    </section>
    """
  end

  defp schedule_result(assigns) do
    ~H"""
    <div id="schedule-result" class="border-t border-base-300 px-5 py-4 flex flex-col gap-2">
      <div class="flex items-center justify-between">
        <div class="flex items-center gap-2 text-sm">
          <.icon name="hero-check-circle" class="size-5 text-success" />
          <span>
            Scheduled <strong id="schedule-result-created">{@result.created}</strong>
            {if @result.created == 1, do: "rescrape", else: "rescrapes"}
          </span>
          <span :if={@result.errors != []} class="text-error">
            · {length(@result.errors)} skipped
          </span>
        </div>
        <button type="button" phx-click="dismiss_result" class="btn btn-ghost btn-xs">
          <.icon name="hero-x-mark" class="size-4" />
        </button>
      </div>
      <ul
        :if={@result.errors != []}
        id="schedule-result-errors"
        class="max-h-40 overflow-y-auto text-xs rounded-lg bg-error/5 border border-error/20 divide-y divide-error/10"
      >
        <li :for={{slug, errors} <- @result.errors} class="px-3 py-1.5 flex gap-2">
          <span class="font-medium">{slug}</span>
          <span class="text-base-content/70">{errors}</span>
        </li>
      </ul>
    </div>
    """
  end

  defp rescrapes_table(assigns) do
    ~H"""
    <section class="flex flex-col gap-3">
      <div class="flex flex-wrap items-center justify-between gap-3">
        <h2 class="font-semibold">
          {status_filter_title(@status_filter)}
          <span class="text-base-content/50 font-normal tabular-nums">({@rescrapes_count})</span>
        </h2>
        <.form for={%{}} id="rescrapes-filter-form" phx-change="filter_search" class="w-72">
          <input
            id="rescrapes-search-input"
            type="text"
            name="search"
            value={@search}
            placeholder="Filter by project slug or name"
            phx-debounce="300"
            class="input input-sm w-full"
          />
        </.form>
      </div>

      <div class="rounded-2xl border border-base-300 bg-base-100 overflow-x-auto">
        <table class="table table-sm">
          <thead>
            <tr class="text-xs uppercase tracking-wide text-base-content/60">
              <th>Project</th>
              <th>Interval</th>
              <th>Status</th>
              <th class="min-w-56">Progress</th>
              <th>Priority</th>
              <th>Timing</th>
              <th><span class="sr-only">Actions</span></th>
            </tr>
          </thead>
          <tbody id="rescrapes" phx-update="stream">
            <tr id="rescrapes-empty" class="hidden only:table-row">
              <td colspan="7" class="text-center text-base-content/50 py-10">
                No rescrapes here.
              </td>
            </tr>
            <tr
              :for={{dom_id, srp} <- @streams.rescrapes}
              id={dom_id}
              class="hover:bg-base-200/50 transition-colors align-top"
            >
              <.rescrape_row srp={srp} now={@now} can_edit?={@can_edit?} />
            </tr>
          </tbody>
        </table>
      </div>
    </section>
    """
  end

  defp rescrape_row(assigns) do
    srp = assigns.srp
    progress = ScheduleRescrapePrice.progress(srp, assigns.now)

    assigns =
      assign(assigns,
        progress: progress,
        activity: activity_text(srp, assigns.now),
        eta: eta(srp, progress, assigns.now),
        active?: ScheduleRescrapePrice.active?(srp)
      )

    ~H"""
    <td>
      <div class="font-medium">{@srp.project.name}</div>
      <.link
        href={~p"/admin/generic/#{@srp.project_id}?resource=projects"}
        class="text-xs text-base-content/50 link link-hover"
      >
        {@srp.project.slug}
      </.link>
    </td>
    <td class="text-xs tabular-nums whitespace-nowrap">
      <div>{format_datetime(@srp.from)}</div>
      <div class="text-base-content/50">→ {format_datetime(@srp.to)}</div>
      <div class="text-base-content/40">
        {format_duration(NaiveDateTime.diff(@srp.to, @srp.from))}
      </div>
    </td>
    <td>
      <.status_badge status={@srp.status} />
      <div :if={@activity} class="text-xs text-base-content/50 mt-1">{@activity}</div>
    </td>
    <td>
      <div class="flex items-center gap-2">
        <div class="h-2 flex-1 rounded-full bg-base-200 overflow-hidden">
          <div
            class={[
              "h-full rounded-full transition-all duration-700 ease-out",
              progress_bar_class(@srp.status)
            ]}
            style={"width: #{Float.round(@progress * 100, 1)}%"}
          >
          </div>
        </div>
        <span class="text-xs tabular-nums w-12 text-right">{format_percent(@progress)}</span>
      </div>
      <div :if={@srp.progress_datetime} class="text-xs text-base-content/50 mt-1 tabular-nums">
        at {format_datetime(@srp.progress_datetime)}
      </div>
      <div
        :if={@srp.last_error}
        class="text-xs text-error mt-1 line-clamp-2 max-w-sm"
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
          {Phoenix.HTML.Form.options_for_select(
            ["high", "normal", "low"],
            to_string(@srp.priority)
          )}
        </select>
      </.form>
      <span :if={not (@can_edit? and @active?)} class="text-sm">{@srp.priority}</span>
    </td>
    <td class="text-xs text-base-content/70 whitespace-nowrap">
      <div>created {rough_duration_since(@srp.inserted_at)} ago</div>
      <div :if={@srp.started_at && @active?}>
        running for {format_duration(NaiveDateTime.diff(@now, @srp.started_at))}
      </div>
      <div :if={@eta} class="text-info">{@eta}</div>
      <div :if={@srp.finished_at && !@active?}>
        ended {rough_duration_since(@srp.finished_at)} ago
      </div>
    </td>
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
        class="btn btn-ghost btn-xs text-primary"
      >
        Resume
      </button>
      <.link
        href={~p"/admin/generic/#{@srp.id}?resource=schedule_rescrape_prices"}
        class="btn btn-ghost btn-xs"
        title="Open in the generic admin"
      >
        <.icon name="hero-arrow-top-right-on-square" class="size-3.5" />
      </.link>
    </td>
    """
  end

  defp status_badge(assigns) do
    ~H"""
    <span class={["badge badge-sm gap-1", status_badge_class(@status)]}>
      <span :if={@status == :running} class="loading loading-ring loading-xs"></span>
      {@status}
    </span>
    """
  end

  # ─── Helpers ─────────────────────────────────────────────────────────────

  defp load_rescrapes(socket) do
    rescrapes =
      ScheduleRescrapePrice.list(
        status: status_filter_to_opt(socket.assigns.status_filter),
        search: String.trim(socket.assigns.search)
      )

    socket
    |> assign(
      now: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
      counts: ScheduleRescrapePrice.status_counts(),
      rescrapes_count: length(rescrapes)
    )
    |> stream(:rescrapes, rescrapes, reset: true)
  end

  defp with_rescrape(socket, id, fun) do
    socket =
      if socket.assigns.can_edit? do
        case ScheduleRescrapePrice.by_id(String.to_integer(id)) do
          {:ok, srp} ->
            {kind, message} = fun.(srp)
            put_flash(socket, kind, message)

          {:error, error} ->
            put_flash(socket, :error, error)
        end
      else
        put_flash(socket, :error, "You need the Admin Panel Editor role to do this.")
      end

    {:noreply, load_rescrapes(socket)}
  end

  # Runs in a task, so scheduling all the projects does not block the page
  defp schedule(nil, from, to, priority) do
    projects = Sanbase.Project.List.projects_with_source("coinmarketcap", include_hidden: true)
    schedule(projects, from, to, priority)
  end

  defp schedule(projects, from, to, priority) do
    errors =
      ScheduleRescrapeHelpers.run(from, to, projects: projects, priority: priority)
      |> Enum.map(fn {slug, errors} -> {slug, format_errors(errors)} end)

    {length(projects), errors}
  end

  defp add_selected_projects(socket, projects) do
    selected = Enum.uniq_by(socket.assigns.selected_projects ++ projects, & &1.slug)
    assign(socket, :selected_projects, selected)
  end

  defp assign_schedule_form(socket, params, action \\ nil) do
    form = params |> schedule_changeset() |> to_form(as: :rescrape, action: action)
    assign(socket, schedule_params: params, schedule_form: form)
  end

  defp schedule_changeset(params) do
    priorities = Enum.map(ScheduleRescrapePrice.priorities(), &to_string/1)

    {%{}, @schedule_types}
    |> Ecto.Changeset.cast(params, Map.keys(@schedule_types))
    |> Ecto.Changeset.validate_required([:from, :to, :priority])
    |> Ecto.Changeset.validate_inclusion(:priority, priorities)
    |> validate_from_before_to()
  end

  defp validate_from_before_to(changeset) do
    from = Ecto.Changeset.get_field(changeset, :from)
    to = Ecto.Changeset.get_field(changeset, :to)

    if from && to && NaiveDateTime.compare(from, to) != :lt do
      Ecto.Changeset.add_error(changeset, :to, "must be after `from`")
    else
      changeset
    end
  end

  defp errors_to_string(%Ecto.Changeset{} = changeset) do
    changeset |> Sanbase.Utils.ErrorHandling.changeset_errors() |> format_errors()
  end

  defp format_errors(errors) when is_map(errors) do
    Enum.map_join(errors, "; ", fn
      {:project_id, messages} -> Enum.join(messages, ", ")
      {field, messages} -> "#{field} #{Enum.join(messages, ", ")}"
    end)
  end

  defp status_filter_to_opt("all"), do: nil
  defp status_filter_to_opt(status), do: String.to_existing_atom(status)

  defp status_filter_title("all"), do: "All rescrapes"
  defp status_filter_title("active"), do: "Active rescrapes"
  defp status_filter_title(status), do: String.capitalize(status) <> " rescrapes"

  defp active_count(counts), do: Map.get(counts, :running, 0) + Map.get(counts, :pending, 0)

  defp schedule_button_text(true, _all?, _count), do: "Scheduling…"
  defp schedule_button_text(false, true, _count), do: "Schedule for all projects"
  defp schedule_button_text(false, false, 1), do: "Schedule 1 rescrape"
  defp schedule_button_text(false, false, count), do: "Schedule #{count} rescrapes"

  defp status_badge_class(:running), do: "badge-success badge-soft"
  defp status_badge_class(:pending), do: "badge-warning badge-soft"
  defp status_badge_class(:finished), do: "badge-ghost"
  defp status_badge_class(:failed), do: "badge-error badge-soft"
  defp status_badge_class(:cancelled), do: "badge-ghost opacity-60"

  defp progress_bar_class(:running), do: "bg-success"
  defp progress_bar_class(:pending), do: "bg-warning"
  defp progress_bar_class(:finished), do: "bg-base-content/30"
  defp progress_bar_class(:failed), do: "bg-error"
  defp progress_bar_class(:cancelled), do: "bg-base-content/20"

  # A running rescrape with an error is waiting to retry the failed day
  defp activity_text(%{status: :pending}, _now), do: "waiting for a free slot"

  defp activity_text(%{status: :running, last_error: error}, _now) when is_binary(error),
    do: "retrying after an error"

  defp activity_text(%{status: :running, updated_at: updated_at}, now),
    do: "last progress #{format_duration(NaiveDateTime.diff(now, updated_at))} ago"

  defp activity_text(_srp, _now), do: nil

  # A rough estimate from the speed since the rescrape started
  defp eta(
         %ScheduleRescrapePrice{status: :running, started_at: %NaiveDateTime{} = started},
         progress,
         now
       )
       when progress > 0 and progress < 1 do
    elapsed = NaiveDateTime.diff(now, started)
    if elapsed > 0, do: "≈ #{format_duration(round(elapsed / progress * (1 - progress)))} left"
  end

  defp eta(_srp, _progress, _now), do: nil

  defp format_percent(progress), do: "#{round(progress * 100)}%"

  defp format_datetime(%NaiveDateTime{} = ndt), do: Calendar.strftime(ndt, "%Y-%m-%d %H:%M")

  defp format_duration(seconds) when seconds < 60, do: "#{max(seconds, 0)}s"
  defp format_duration(seconds) when seconds < 3600, do: "#{div(seconds, 60)}m"

  defp format_duration(seconds) when seconds < 86_400,
    do: "#{div(seconds, 3600)}h #{div(rem(seconds, 3600), 60)}m"

  defp format_duration(seconds),
    do: "#{div(seconds, 86_400)}d #{div(rem(seconds, 86_400), 3600)}h"

  defp datetime_local(%NaiveDateTime{} = ndt),
    do: ndt |> NaiveDateTime.to_iso8601() |> String.slice(0, 16)
end
