defmodule SanbaseWeb.Admin.HomeStatsLive do
  @moduledoc """
  Embedded LiveView for the admin home page stats. Mounts with `layout: false`
  so it can be `live_render`'d inside the controller-rendered admin home
  template. Stats load asynchronously via `assign_async/3` so the surrounding
  page shell (incl. sidebar) paints immediately while the cache cold-load
  completes in the background.
  """
  use SanbaseWeb, :live_view

  import SanbaseWeb.GenericAdminHTML, only: [stat_card: 1, daily_sparkline: 1]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign_async(:stats, fn -> {:ok, %{stats: SanbaseWeb.Admin.Stats.get()}} end),
     layout: false}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <.async_result :let={stats} assign={@stats}>
        <:loading>
          <.loading_skeleton />
        </:loading>
        <:failed :let={_reason}>
          <div class="alert alert-error">
            Failed to load stats. Refresh to retry.
          </div>
        </:failed>

        <p class="text-sm text-base-content/60">
          Updated {Calendar.strftime(stats.computed_at, "%Y-%m-%d %H:%M UTC")} · cached for 15 min
        </p>

        <section>
          <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/60 mb-2">
            Users
          </h2>
          <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-2">
            <.stat_card label="Total Users" value={stats.users.total} />
            <.stat_card label="Signups · 24h" value={stats.users.last_24h} />
            <.stat_card label="Signups · 7d" value={stats.users.last_7d} />
          </div>
        </section>

        <section>
          <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/60 mb-2">
            Metric Registry
          </h2>
          <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-2">
            <.stat_card
              label="Total"
              value={stats.metric_registry.total}
              href="/admin/metric_registry"
            />
            <.stat_card
              label="Not Synced"
              value={stats.metric_registry.not_synced}
              accent={(stats.metric_registry.not_synced > 0 && "text-warning") || nil}
            />
            <.stat_card label="Unverified" value={stats.metric_registry.unverified} />
            <.stat_card label="Deprecated" value={stats.metric_registry.deprecated} />
            <.stat_card
              label="Pending Approval"
              value={stats.metric_registry.pending_approval}
              accent={(stats.metric_registry.pending_approval > 0 && "text-info") || nil}
            />
          </div>
        </section>

        <section>
          <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/60 mb-2">
            Active Subscriptions · Sanbase
          </h2>
          <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-2">
            <.stat_card label="Total" value={stats.subscriptions.sanbase.total} />
            <.stat_card
              :for={{plan, count} <- stats.subscriptions.sanbase.by_plan}
              label={plan}
              value={count}
            />
          </div>
        </section>

        <section>
          <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/60 mb-2">
            Active Subscriptions · SanAPI
          </h2>
          <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-2">
            <.stat_card label="Total" value={stats.subscriptions.sanapi.total} />
            <.stat_card
              :for={{plan, count} <- stats.subscriptions.sanapi.by_plan}
              label={plan}
              value={count}
            />
          </div>
        </section>

        <section>
          <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/60 mb-2">
            Oban Queues
          </h2>
          <div class="overflow-x-auto bg-base-100 border border-base-300 rounded">
            <table class="table table-sm">
              <thead>
                <tr class="text-base-content/60">
                  <th>Queue</th>
                  <th class="text-right">Scheduled</th>
                  <th class="text-right">Executing</th>
                  <th class="text-right">Completed · 1d</th>
                  <th class="text-right">Completed · 7d</th>
                  <th class="text-right">Discarded · 7d</th>
                  <th class="text-right">Cancelled · 7d</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={q <- stats.oban} class="hover:bg-base-200">
                  <td class="font-medium">{q.queue}</td>
                  <td class="text-right tabular-nums">{q.scheduled}</td>
                  <td class="text-right tabular-nums">{q.executing}</td>
                  <td class="text-right tabular-nums">{q.completed_1d}</td>
                  <td class="text-right tabular-nums">{q.completed_7d}</td>
                  <td class={[
                    "text-right tabular-nums",
                    q.discarded_7d > 0 && "text-error font-semibold"
                  ]}>
                    {q.discarded_7d}
                  </td>
                  <td class={[
                    "text-right tabular-nums",
                    q.cancelled_7d > 0 && "text-warning font-semibold"
                  ]}>
                    {q.cancelled_7d}
                  </td>
                </tr>
                <tr :if={stats.oban == []}>
                  <td colspan="7" class="text-center text-base-content/50">No jobs</td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>

        <section>
          <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/60 mb-2">
            Last {stats.series.days} Days
          </h2>
          <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-2">
            <.daily_sparkline label="Signups" series={stats.series} key={:users} />
            <.daily_sparkline label="Watchlists" series={stats.series} key={:watchlists} />
            <.daily_sparkline
              label="Chart Configurations"
              series={stats.series}
              key={:chart_configurations}
            />
            <.daily_sparkline label="Alerts Created" series={stats.series} key={:alerts} />
            <.daily_sparkline label="Alerts Fired" series={stats.series} key={:alerts_fired} />
            <.daily_sparkline label="Insights" series={stats.series} key={:insights} />
            <.daily_sparkline label="Comments" series={stats.series} key={:comments} />
            <.daily_sparkline label="Promo Trials" series={stats.series} key={:promo_trials} />
          </div>
        </section>

        <section>
          <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/60 mb-2">
            Content
          </h2>
          <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-2">
            <.stat_card label="Insights" value={stats.insights.total} />
            <.stat_card label="Comments" value={stats.comments.total} />
            <.stat_card label="Disagreement Tweets" value={stats.disagreement_tweets.total} />
            <.stat_card
              label="Tweets to Review"
              value={stats.disagreement_tweets.review_required}
              accent={(stats.disagreement_tweets.review_required > 0 && "text-warning") || nil}
            />
            <.stat_card label="FAQ Active" value={stats.faq_entries.active} />
          </div>
        </section>
      </.async_result>
    </div>
    """
  end

  defp loading_skeleton(assigns) do
    ~H"""
    <div class="space-y-4 animate-pulse">
      <div class="h-3 w-64 bg-base-300 rounded"></div>
      <div :for={_ <- 1..3} class="space-y-2">
        <div class="h-3 w-32 bg-base-300 rounded"></div>
        <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-2">
          <div :for={_ <- 1..5} class="h-8 bg-base-300 rounded"></div>
        </div>
      </div>
    </div>
    """
  end
end
