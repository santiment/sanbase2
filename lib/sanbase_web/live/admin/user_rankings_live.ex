defmodule SanbaseWeb.Admin.UserRankingsLive do
  @moduledoc """
  Read-only leaderboard of the heaviest content creators (team users excluded),
  for spotting power-users and potential abuse. Sortable by any count or depth
  metric; each row links to the per-user overview. Backed by the cached
  single-query `SanbaseWeb.Admin.UserRankings`.
  """
  use SanbaseWeb, :live_view

  alias SanbaseWeb.Admin.UserRankings

  @rank_labels [
    total_creations: "Total creations",
    charts: "Charts",
    max_chart_metrics: "Deepest chart (metrics)",
    total_chart_metrics: "Total chart metrics",
    insights: "Insights",
    dashboards: "Dashboards",
    watchlists: "Watchlists",
    screeners: "Screeners",
    max_watchlist_assets: "Largest watchlist (assets)",
    alerts: "Alerts",
    queries: "SQL queries",
    addresses: "Addresses",
    api_keys: "API keys"
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "User Rankings")
     |> assign(:rank_by, :total_creations)
     |> assign(:limit, 200)
     |> load_rows(:total_creations, 200)}
  end

  @impl true
  def handle_event("rank", %{"rank_by" => rank_by, "limit" => limit}, socket) do
    rank_by =
      Enum.find(UserRankings.rank_options(), :total_creations, &(Atom.to_string(&1) == rank_by))

    limit =
      case Integer.parse(limit) do
        {n, _} -> n
        :error -> 200
      end

    {:noreply,
     socket
     |> assign(:rank_by, rank_by)
     |> assign(:limit, limit)
     |> load_rows(rank_by, limit)}
  end

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
    assigns = assign(assigns, :rank_labels, @rank_labels)

    ~H"""
    <div class="space-y-4">
      <div class="flex items-baseline justify-between">
        <h1 class="text-xl font-semibold">User Rankings</h1>
        <.link navigate={~p"/admin/user_overview"} class="btn btn-sm btn-soft">
          <.icon name="hero-magnifying-glass" class="size-4" /> Look up user
        </.link>
      </div>

      <form phx-change="rank" class="flex flex-wrap items-end gap-2">
        <label class="form-control">
          <span class="label-text text-xs">Rank by</span>
          <select name="rank_by" class="select select-bordered select-sm">
            <option :for={{value, label} <- @rank_labels} value={value} selected={value == @rank_by}>
              {label}
            </option>
          </select>
        </label>
        <label class="form-control">
          <span class="label-text text-xs">Top</span>
          <select name="limit" class="select select-bordered select-sm">
            <option :for={n <- [50, 100, 200, 500, 1000]} value={n} selected={n == @limit}>
              {n}
            </option>
          </select>
        </label>
        <.link
          href={~p"/admin/user_rankings/export?rank_by=#{@rank_by}&limit=#{@limit}"}
          class="btn btn-sm btn-soft"
        >
          <.icon name="hero-arrow-down-tray" class="size-4" /> Save as CSV
        </.link>
      </form>

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
                <th>Paid</th>
                <th class="text-right">Total</th>
                <th class="text-right">Charts</th>
                <th class="text-right">Max metrics</th>
                <th class="text-right">Insights</th>
                <th class="text-right">Dashboards</th>
                <th class="text-right">Watchlists</th>
                <th class="text-right">Screeners</th>
                <th class="text-right">Max assets</th>
                <th class="text-right">Alerts</th>
                <th class="text-right">Queries</th>
                <th class="text-right">API keys</th>
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
                <td class="text-right tabular-nums">{row.insights}</td>
                <td class="text-right tabular-nums">{row.dashboards}</td>
                <td class="text-right tabular-nums">{row.watchlists}</td>
                <td class="text-right tabular-nums">{row.screeners}</td>
                <td class="text-right tabular-nums">{row.max_watchlist_assets}</td>
                <td class="text-right tabular-nums">{row.alerts}</td>
                <td class="text-right tabular-nums">{row.queries}</td>
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
                <td colspan="15" class="text-center text-base-content/50">No creators found</td>
              </tr>
            </tbody>
          </table>
        </div>
      </.async_result>
    </div>
    """
  end

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
