defmodule SanbaseWeb.Admin.UserRankingsLive do
  @moduledoc """
  Read-only leaderboard of the heaviest content creators (team users excluded),
  for spotting power-users and potential abuse. Sort by clicking any column
  header; the active sort and page size live in the query string, so the
  browser Back button restores the previous view and the URL is shareable.
  Each row links to the per-user overview. Backed by the cached single-query
  `SanbaseWeb.Admin.UserRankings`.
  """
  use SanbaseWeb, :live_view

  alias SanbaseWeb.Admin.UserRankings

  @default_rank :total_creations
  @default_limit 200
  @limit_options [50, 100, 200, 500, 1000]

  @impl true
  def mount(_params, _session, socket) do
    # The actual rows are loaded in handle_params/3, which runs after mount on
    # the initial render and again on every push_patch (header click / limit
    # change), so the URL is always the single source of truth.
    {:ok, assign(socket, :page_title, "User Rankings")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    rank_by = parse_rank_by(params["rank_by"])
    limit = parse_limit(params["limit"])

    {:noreply,
     socket
     |> assign(:rank_by, rank_by)
     |> assign(:limit, limit)
     |> load_rows(rank_by, limit)}
  end

  # Changing the page-size select pushes a patch that keeps the current sort
  # column; the header links carry the sort and keep the current limit. Both
  # funnel through handle_params/3 above.
  @impl true
  def handle_event("set_limit", %{"limit" => limit}, socket) do
    {:noreply,
     push_patch(socket,
       to: ~p"/admin/user_rankings?rank_by=#{socket.assigns.rank_by}&limit=#{parse_limit(limit)}"
     )}
  end

  defp parse_rank_by(nil), do: @default_rank

  defp parse_rank_by(value) when is_binary(value) do
    Enum.find(UserRankings.rank_options(), @default_rank, &(Atom.to_string(&1) == value))
  end

  defp parse_limit(value) when is_integer(value) and value > 0, do: min(value, 1000)

  defp parse_limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, _} -> parse_limit(n)
      :error -> @default_limit
    end
  end

  defp parse_limit(_), do: @default_limit

  defp load_rows(socket, rank_by, limit) do
    assign_async(socket, :ranking, fn ->
      case UserRankings.get(rank_by: rank_by, limit: limit) do
        {:ok, ranking} -> {:ok, %{ranking: ranking}}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :limit_options, @limit_options)

    ~H"""
    <div class="space-y-4">
      <div class="flex items-baseline justify-between">
        <h1 class="text-xl font-semibold">User Rankings</h1>
        <.link navigate={~p"/admin/user_overview"} class="btn btn-sm btn-soft">
          <.icon name="hero-magnifying-glass" class="size-4" /> Look up user
        </.link>
      </div>

      <div class="flex flex-wrap items-end gap-2">
        <form phx-change="set_limit">
          <label class="form-control">
            <span class="label-text text-xs">Top</span>
            <select name="limit" class="select select-bordered select-sm">
              <option :for={n <- @limit_options} value={n} selected={n == @limit}>{n}</option>
            </select>
          </label>
        </form>
        <p class="text-xs text-base-content/50 pb-1">
          Sort by clicking a column header.
        </p>
        <.link
          href={~p"/admin/user_rankings/export?rank_by=#{@rank_by}&limit=#{@limit}"}
          class="btn btn-sm btn-soft ml-auto"
        >
          <.icon name="hero-arrow-down-tray" class="size-4" /> Save as CSV
        </.link>
      </div>

      <.async_result :let={ranking} assign={@ranking}>
        <:loading>
          <div class="space-y-2 animate-pulse">
            <div :for={_ <- 1..10} class="h-6 bg-base-300 rounded"></div>
          </div>
        </:loading>
        <:failed :let={reason}>
          <div class="alert alert-error">Could not load rankings: {inspect(reason)}</div>
        </:failed>

        <p class="text-sm text-base-content/60">
          Top {length(ranking.rows)} creators · excludes @santiment.net · updated {Calendar.strftime(
            ranking.computed_at,
            "%Y-%m-%d %H:%M UTC"
          )} · cached 15 min
        </p>

        <div class="overflow-x-auto bg-base-100 border border-base-300 rounded">
          <table class="table table-sm table-pin-rows">
            <thead>
              <tr class="text-base-content/60">
                <th class="text-right">#</th>
                <th>User</th>
                <.sort_th
                  col={:last_active}
                  label="Last active"
                  rank_by={@rank_by}
                  limit={@limit}
                  align="left"
                  title="Last web/app session activity (JWT refresh, ~5-min resolution). Excludes API-key traffic."
                />
                <th>Paid</th>
                <.sort_th col={:total_creations} label="Total" rank_by={@rank_by} limit={@limit} />
                <.sort_th col={:charts} label="Charts" rank_by={@rank_by} limit={@limit} />
                <.sort_th
                  col={:max_chart_metrics}
                  label="Max metrics"
                  rank_by={@rank_by}
                  limit={@limit}
                />
                <.sort_th
                  col={:total_chart_metrics}
                  label="Total metrics"
                  rank_by={@rank_by}
                  limit={@limit}
                />
                <.sort_th col={:insights} label="Insights" rank_by={@rank_by} limit={@limit} />
                <.sort_th col={:dashboards} label="Dashboards" rank_by={@rank_by} limit={@limit} />
                <.sort_th col={:watchlists} label="Watchlists" rank_by={@rank_by} limit={@limit} />
                <.sort_th col={:screeners} label="Screeners" rank_by={@rank_by} limit={@limit} />
                <.sort_th
                  col={:max_watchlist_assets}
                  label="Max assets"
                  rank_by={@rank_by}
                  limit={@limit}
                />
                <.sort_th col={:alerts} label="Alerts" rank_by={@rank_by} limit={@limit} />
                <.sort_th col={:queries} label="Queries" rank_by={@rank_by} limit={@limit} />
                <.sort_th col={:addresses} label="Addresses" rank_by={@rank_by} limit={@limit} />
                <.sort_th col={:api_keys} label="API keys" rank_by={@rank_by} limit={@limit} />
                <th>Flags</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={{row, idx} <- Enum.with_index(ranking.rows, 1)} class="hover:bg-base-200">
                <td class="text-right text-base-content/50 tabular-nums">{idx}</td>
                <td>
                  <.link
                    navigate={~p"/admin/user_overview?user_id=#{row.user_id}"}
                    class="link link-hover font-medium"
                  >
                    {row.email || row.username || "##{row.user_id}"}
                  </.link>
                </td>
                <td
                  class="whitespace-nowrap text-base-content/70 tabular-nums"
                  title={fmt_last_active_full(row.last_active)}
                >
                  {fmt_last_active(row.last_active)}
                </td>
                <td>
                  <span class={["badge badge-xs", (row.is_paid && "badge-success") || "badge-ghost"]}>
                    {(row.is_paid && "paid") || "free"}
                  </span>
                </td>
                <td class="text-right tabular-nums font-semibold">{row.total_creations}</td>
                <td class="text-right tabular-nums">{row.charts}</td>
                <td class="text-right tabular-nums">
                  <span class={(row.max_chart_metrics > 100 && "text-warning font-semibold") || ""}>
                    {row.max_chart_metrics}
                  </span>
                </td>
                <td class="text-right tabular-nums">{row.total_chart_metrics}</td>
                <td class="text-right tabular-nums">{row.insights}</td>
                <td class="text-right tabular-nums">{row.dashboards}</td>
                <td class="text-right tabular-nums">{row.watchlists}</td>
                <td class="text-right tabular-nums">{row.screeners}</td>
                <td class="text-right tabular-nums">{row.max_watchlist_assets}</td>
                <td class="text-right tabular-nums">{row.alerts}</td>
                <td class="text-right tabular-nums">{row.queries}</td>
                <td class="text-right tabular-nums">{row.addresses}</td>
                <td class="text-right tabular-nums">{row.api_keys}</td>
                <td>
                  <div class="flex flex-wrap gap-1">
                    <span
                      :for={{key, reason} <- row.flags}
                      class={["badge badge-xs", flag_class(key)]}
                      title={reason}
                    >
                      {flag_label(key)}
                    </span>
                  </div>
                </td>
              </tr>
              <tr :if={ranking.rows == []}>
                <td colspan="18" class="text-center text-base-content/50">No creators found</td>
              </tr>
            </tbody>
          </table>
        </div>
      </.async_result>
    </div>
    """
  end

  # ── Components ─────────────────────────────────────────────────────────────

  # A sortable column header. Clicking it patches the URL to sort by `col` while
  # keeping the current page size. The active column is bold with a solid ▼;
  # the others show a faint ▼ to signal they are clickable.
  attr :col, :atom, required: true
  attr :label, :string, required: true
  attr :rank_by, :atom, required: true
  attr :limit, :integer, required: true
  attr :align, :string, default: "right"
  attr :title, :string, default: nil

  defp sort_th(assigns) do
    assigns = assign(assigns, :active, assigns.rank_by == assigns.col)

    ~H"""
    <th class={(@align == "right" && "text-right") || "text-left"}>
      <.link
        patch={~p"/admin/user_rankings?rank_by=#{@col}&limit=#{@limit}"}
        title={@title}
        class={[
          "inline-flex items-center gap-0.5 select-none hover:text-base-content",
          (@align == "right" && "justify-end") || "justify-start",
          @active && "text-base-content font-semibold"
        ]}
      >
        {@label}
        <span class={["text-[0.6rem]", (@active && "opacity-100") || "opacity-30"]}>▼</span>
      </.link>
    </th>
    """
  end

  defp fmt_last_active(nil), do: "—"
  defp fmt_last_active(dt), do: Calendar.strftime(dt, "%Y-%m-%d")

  defp fmt_last_active_full(nil), do: "No web/app session recorded"
  defp fmt_last_active_full(dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")

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
