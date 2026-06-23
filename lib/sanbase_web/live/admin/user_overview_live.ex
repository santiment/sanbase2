defmodule SanbaseWeb.Admin.UserOverviewLive do
  @moduledoc """
  Read-only admin page: look up a single user and see their subscription
  status, everything they've created (with a depth measure per item), and any
  abuse flags. Data is loaded async and cached by `SanbaseWeb.Admin.UserOverview`.
  """
  use SanbaseWeb, :live_view

  import SanbaseWeb.GenericAdminHTML, only: [stat_card: 1]

  alias SanbaseWeb.Admin.UserOverview

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "User Overview")
     |> assign(:term, "")
     |> assign(:error, nil)
     |> assign(:overview, nil)}
  end

  @impl true
  def handle_params(%{"user_id" => user_id}, _uri, socket) do
    case Integer.parse(user_id) do
      {id, _} -> {:noreply, load_user(socket, id)}
      :error -> {:noreply, assign(socket, :error, "Invalid user id #{inspect(user_id)}")}
    end
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_event("search", %{"term" => term}, socket) do
    case UserOverview.lookup(term) do
      {:ok, id} ->
        {:noreply, push_patch(socket, to: ~p"/admin/user_overview?user_id=#{id}")}

      {:error, msg} ->
        {:noreply, socket |> assign(:error, msg) |> assign(:term, term) |> assign(:overview, nil)}
    end
  end

  defp load_user(socket, id) do
    socket
    |> assign(:error, nil)
    |> assign(:term, to_string(id))
    |> assign_async(:overview, fn ->
      case UserOverview.get(id) do
        {:ok, overview} -> {:ok, %{overview: overview}}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex items-baseline justify-between">
        <h1 class="text-xl font-semibold">User Overview</h1>
        <.link navigate={~p"/admin/user_rankings"} class="btn btn-sm btn-soft">
          <.icon name="hero-trophy" class="size-4" /> Rankings
        </.link>
      </div>

      <form phx-submit="search" class="flex gap-2 max-w-xl">
        <input
          type="text"
          name="term"
          value={@term}
          placeholder="user id, email or username"
          class="input input-bordered input-sm w-full"
          autocomplete="off"
        />
        <button type="submit" class="btn btn-sm btn-primary">Look up</button>
      </form>

      <div :if={@error} class="alert alert-warning">{@error}</div>

      <.async_result :let={ov} :if={@overview} assign={@overview}>
        <:loading>
          <div class="space-y-3 animate-pulse">
            <div class="h-4 w-72 bg-base-300 rounded"></div>
            <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-2">
              <div :for={_ <- 1..10} class="h-12 bg-base-300 rounded"></div>
            </div>
          </div>
        </:loading>
        <:failed :let={reason}>
          <div class="alert alert-error">Could not load user: {inspect(reason)}</div>
        </:failed>

        <.user_header user={ov.user} flags={ov.flags} />
        <.subscription_panel subscription={ov.subscription} />
        <.creations_summary creations={ov.creations} totals={ov.totals} />
        <.depth_tables creations={ov.creations} />

        <p class="text-xs text-base-content/50">
          Computed {Calendar.strftime(ov.computed_at, "%Y-%m-%d %H:%M UTC")} · cached for 5 min
        </p>
      </.async_result>
    </div>
    """
  end

  # ── Components ─────────────────────────────────────────────────────────────

  attr :user, :map, required: true
  attr :flags, :list, required: true

  defp user_header(assigns) do
    ~H"""
    <section class="bg-base-100 border border-base-300 rounded p-3 space-y-2">
      <div class="flex items-center gap-2 flex-wrap">
        <span class="text-lg font-semibold">{@user.email || "(no email)"}</span>
        <span class="text-base-content/50">#{@user.id}</span>
        <span :if={@user.username} class="text-base-content/60">· {@user.username}</span>
        <span :if={@user.is_team} class="badge badge-info badge-sm">TEAM</span>
        <span class="text-xs text-base-content/50">
          · joined {Calendar.strftime(@user.inserted_at, "%Y-%m-%d")}
        </span>
        <.link
          href={~p"/admin/generic/#{@user.id}?resource=users"}
          class="btn btn-xs btn-soft ml-auto"
        >
          <.icon name="hero-cog-6-tooth" class="size-3" /> Admin record
        </.link>
      </div>

      <div :if={@user.is_team} class="text-xs text-info">
        Team account (@santiment.net) — excluded from rankings and abuse flags.
      </div>

      <div :if={@flags != []} class="flex flex-wrap gap-1">
        <span
          :for={{key, reason} <- @flags}
          class={["badge badge-sm", flag_class(key)]}
          title={reason}
        >
          {flag_label(key)}
        </span>
      </div>
    </section>
    """
  end

  attr :subscription, :map, required: true

  defp subscription_panel(assigns) do
    ~H"""
    <section class="space-y-2">
      <div class="flex items-center gap-2">
        <.section_heading>Subscription</.section_heading>
        <span class={["badge badge-sm", (@subscription.is_paid && "badge-success") || "badge-ghost"]}>
          {(@subscription.is_paid && "PAID") || "FREE"}
        </span>
      </div>

      <div :if={@subscription.current != []} class="text-sm">
        <span class="text-base-content/60">Current:</span>
        <span :for={s <- @subscription.current} class="badge badge-outline badge-sm ml-1">
          {s.product}/{s.plan} · {s.status}
        </span>
      </div>

      <div class="overflow-x-auto bg-base-100 border border-base-300 rounded">
        <table class="table table-sm">
          <thead>
            <tr class="text-base-content/60">
              <th>Product</th>
              <th>Plan</th>
              <th>Status</th>
              <th>Type</th>
              <th>Period end</th>
              <th>Trial end</th>
              <th>Cancel@end</th>
              <th>Created</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={s <- @subscription.all} class="hover:bg-base-200">
              <td class="font-medium">{s.product || "—"}</td>
              <td>{s.plan || "—"}</td>
              <td>{s.status}</td>
              <td>{s.type}</td>
              <td>{fmt_date(s.current_period_end)}</td>
              <td>{fmt_date(s.trial_end)}</td>
              <td>{(s.cancel_at_period_end && "yes") || "—"}</td>
              <td>{fmt_date(s.inserted_at)}</td>
            </tr>
            <tr :if={@subscription.all == []}>
              <td colspan="8" class="text-center text-base-content/50">No subscriptions</td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>
    """
  end

  attr :creations, :map, required: true
  attr :totals, :map, required: true

  defp creations_summary(assigns) do
    ~H"""
    <section>
      <.section_heading>Creations</.section_heading>
      <div class="grid gap-2 grid-cols-2 sm:grid-cols-3 lg:grid-cols-6">
        <.stat_card label="Insights" value={@creations.insights.count} />
        <.stat_card label="Charts" value={@creations.charts.count} />
        <.stat_card label="Dashboards" value={@creations.dashboards.count} />
        <.stat_card label="Watchlists" value={@creations.watchlists.count} />
        <.stat_card label="Screeners" value={@creations.screeners.count} />
        <.stat_card label="Alerts" value={@creations.alerts.count} />
        <.stat_card label="Queries" value={@creations.queries.count} />
        <.stat_card label="Addresses" value={@creations.addresses.count} />
        <.stat_card label="API keys" value={@creations.api_keys.count} />
        <.stat_card label="Total creations" value={@totals.total_creations} />
        <.stat_card
          label="Deepest chart (metrics)"
          value={@totals.max_chart_metrics}
          accent={(@totals.max_chart_metrics > 100 && "text-warning") || nil}
        />
        <.stat_card
          label="Largest watchlist (assets)"
          value={@totals.max_watchlist_assets}
          accent={(@totals.max_watchlist_assets > 500 && "text-warning") || nil}
        />
      </div>
    </section>
    """
  end

  attr :creations, :map, required: true

  defp depth_tables(assigns) do
    ~H"""
    <div class="space-y-4">
      <.depth_section title="Charts (by metric depth)" empty="No charts">
        <:head>
          <th>Title</th>
          <th class="text-right">Metrics</th>
          <th class="text-right">Config size (B)</th>
          <th>Public</th>
          <th>Created</th>
        </:head>
        <tr :for={c <- @creations.charts.list} class="hover:bg-base-200">
          <td class="font-medium">
            {c.title || "(untitled)"} <span class="text-base-content/40">#{c.id}</span>
          </td>
          <td class="text-right tabular-nums">
            <span class={(c.metrics > 100 && "text-warning font-semibold") || ""}>{c.metrics}</span>
          </td>
          <td class="text-right tabular-nums text-base-content/60">{c.complexity_bytes}</td>
          <td>{(c.is_public && "yes") || "—"}</td>
          <td>{fmt_date(c.inserted_at)}</td>
        </tr>
      </.depth_section>

      <.depth_section title="Watchlists (by asset count)" empty="No watchlists">
        <:head>
          <th>Name</th>
          <th class="text-right">Assets</th>
          <th>Public</th>
          <th>Created</th>
        </:head>
        <tr :for={w <- @creations.watchlists.list} class="hover:bg-base-200">
          <td class="font-medium">{w.name} <span class="text-base-content/40">#{w.id}</span></td>
          <td class="text-right tabular-nums">{w.assets}</td>
          <td>{(w.is_public && "yes") || "—"}</td>
          <td>{fmt_date(w.inserted_at)}</td>
        </tr>
      </.depth_section>

      <.depth_section title="Screeners (by asset count)" empty="No screeners">
        <:head>
          <th>Name</th>
          <th class="text-right">Assets</th>
          <th>Public</th>
          <th>Created</th>
        </:head>
        <tr :for={w <- @creations.screeners.list} class="hover:bg-base-200">
          <td class="font-medium">{w.name} <span class="text-base-content/40">#{w.id}</span></td>
          <td class="text-right tabular-nums">{w.assets}</td>
          <td>{(w.is_public && "yes") || "—"}</td>
          <td>{fmt_date(w.inserted_at)}</td>
        </tr>
      </.depth_section>

      <.depth_section :if={@creations.dashboards.count > 0} title="Dashboards" empty="No dashboards">
        <:head>
          <th>Name</th>
          <th class="text-right">Widgets</th>
          <th class="text-right">Queries</th>
          <th>Public</th>
          <th>Created</th>
        </:head>
        <tr :for={d <- @creations.dashboards.list} class="hover:bg-base-200">
          <td class="font-medium">
            {d.name || "(untitled)"} <span class="text-base-content/40">#{d.id}</span>
          </td>
          <td class="text-right tabular-nums">{d.widgets}</td>
          <td class="text-right tabular-nums">{d.queries}</td>
          <td>{(d.is_public && "yes") || "—"}</td>
          <td>{fmt_date(d.inserted_at)}</td>
        </tr>
      </.depth_section>

      <.depth_section :if={@creations.insights.count > 0} title="Insights" empty="No insights">
        <:head>
          <th>Title</th>
          <th>Ready</th>
          <th>State</th>
          <th>Created</th>
        </:head>
        <tr :for={p <- @creations.insights.list} class="hover:bg-base-200">
          <td class="font-medium">
            {p.title || "(untitled)"} <span class="text-base-content/40">#{p.id}</span>
          </td>
          <td>{p.ready_state}</td>
          <td>{p.state}</td>
          <td>{fmt_date(p.inserted_at)}</td>
        </tr>
      </.depth_section>

      <.depth_section :if={@creations.alerts.count > 0} title="Alerts" empty="No alerts">
        <:head>
          <th>Title</th>
          <th>Active</th>
          <th>Public</th>
          <th>Created</th>
        </:head>
        <tr :for={a <- @creations.alerts.list} class="hover:bg-base-200">
          <td class="font-medium">
            {a.title || "(untitled)"} <span class="text-base-content/40">#{a.id}</span>
          </td>
          <td>{(a.is_active && "yes") || "—"}</td>
          <td>{(a.is_public && "yes") || "—"}</td>
          <td>{fmt_date(a.inserted_at)}</td>
        </tr>
      </.depth_section>

      <.depth_section :if={@creations.queries.count > 0} title="SQL Queries" empty="No queries">
        <:head>
          <th>Name</th>
          <th>Public</th>
          <th>Created</th>
        </:head>
        <tr :for={q <- @creations.queries.list} class="hover:bg-base-200">
          <td class="font-medium">
            {q.name || "(untitled)"} <span class="text-base-content/40">#{q.id}</span>
          </td>
          <td>{(q.is_public && "yes") || "—"}</td>
          <td>{fmt_date(q.inserted_at)}</td>
        </tr>
      </.depth_section>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :empty, :string, required: true
  slot :head, required: true
  slot :inner_block, required: true

  defp depth_section(assigns) do
    ~H"""
    <section>
      <.section_heading>{@title}</.section_heading>
      <div class="overflow-x-auto bg-base-100 border border-base-300 rounded">
        <table class="table table-sm">
          <thead>
            <tr class="text-base-content/60">{render_slot(@head)}</tr>
          </thead>
          <tbody>
            {render_slot(@inner_block)}
          </tbody>
        </table>
      </div>
    </section>
    """
  end

  slot :inner_block, required: true

  defp section_heading(assigns) do
    ~H"""
    <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/60 mb-2">
      {render_slot(@inner_block)}
    </h2>
    """
  end

  defp fmt_date(nil), do: "—"
  defp fmt_date(dt), do: Calendar.strftime(dt, "%Y-%m-%d")

  defp flag_label(:huge_chart), do: "Huge chart"
  defp flag_label(:deep_chart), do: "Deep chart"
  defp flag_label(:many_charts), do: "Many charts"
  defp flag_label(:huge_watchlist), do: "Huge watchlist"
  defp flag_label(:high_total), do: "High total"
  defp flag_label(:max_api_keys), do: "Max API keys"
  defp flag_label(:free_power_user), do: "Free power-user"
  defp flag_label(other), do: to_string(other)

  defp flag_class(:free_power_user), do: "badge-error"
  defp flag_class(:huge_chart), do: "badge-error"
  defp flag_class(:huge_watchlist), do: "badge-error"
  defp flag_class(_), do: "badge-warning"
end
