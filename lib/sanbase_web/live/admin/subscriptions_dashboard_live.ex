defmodule SanbaseWeb.Admin.SubscriptionsDashboardLive do
  @moduledoc """
  Read-only admin dashboard for tracking subscriptions: status mix, plan
  distribution, internal-vs-external (`@santiment.net`), trialing detail,
  scheduled cancellations, recent activity, and currently-applied Stripe
  discounts (cross-referenced to local subs by `stripe_id`).

  Stats load asynchronously via `assign_async/3` and are cached for 15
  minutes by `SanbaseWeb.Admin.SubscriptionsStats`.
  """
  use SanbaseWeb, :live_view

  import SanbaseWeb.GenericAdminHTML, only: [stat_card: 1]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Subscriptions Dashboard")
     |> assign_async(:stats, fn ->
       case SanbaseWeb.Admin.SubscriptionsStats.get() do
         {:ok, stats} -> {:ok, %{stats: stats}}
         {:error, reason} -> {:error, reason}
       end
     end)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex items-baseline justify-between">
        <h1 class="text-xl font-semibold">Subscriptions Dashboard</h1>
      </div>

      <.async_result :let={stats} assign={@stats}>
        <:loading>
          <.loading_skeleton />
        </:loading>
        <:failed :let={_reason}>
          <div class="alert alert-error">Failed to load subscription stats. Refresh to retry.</div>
        </:failed>

        <p class="text-sm text-base-content/60">
          Updated {Calendar.strftime(stats.computed_at, "%Y-%m-%d %H:%M UTC")} · cached for 15 min
        </p>

        <.stats_section title="Overview" cols="grid-cols-2 sm:grid-cols-3 lg:grid-cols-5">
          <.stat_card label="Total" value={stats.overview.total} />
          <.stat_card label="Active" value={stats.overview.active} />
          <.stat_card label="Trialing" value={stats.overview.trialing} />
          <.stat_card
            label="Past Due"
            value={stats.overview.past_due}
            accent={(stats.overview.past_due > 0 && "text-warning") || nil}
          />
          <.stat_card label="Canceled" value={stats.overview.canceled} />
          <.stat_card label="Incomplete" value={stats.overview.incomplete} />
          <.stat_card
            label="Unpaid"
            value={stats.overview.unpaid}
            accent={(stats.overview.unpaid > 0 && "text-warning") || nil}
          />
          <.stat_card label="Internal Users" value={stats.overview.internal} />
          <.stat_card
            label="Scheduled Cancel"
            value={stats.overview.scheduled_cancellation}
            accent={(stats.overview.scheduled_cancellation > 0 && "text-info") || nil}
          />
        </.stats_section>

        <section>
          <.section_heading>By Status</.section_heading>
          <div class="overflow-x-auto bg-base-100 border border-base-300 rounded">
            <table class="table table-sm">
              <thead>
                <tr class="text-base-content/60">
                  <th>Status</th>
                  <th class="text-right">Count</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={row <- stats.by_status} class="hover:bg-base-200">
                  <td class="font-medium">{row.status}</td>
                  <td class="text-right tabular-nums">{row.count}</td>
                </tr>
                <tr :if={stats.by_status == []}>
                  <td colspan="2" class="text-center text-base-content/50">No data</td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>

        <section>
          <.section_heading>By Product × Plan (active / trialing / past_due)</.section_heading>
          <div class="overflow-x-auto bg-base-100 border border-base-300 rounded">
            <table class="table table-sm">
              <thead>
                <tr class="text-base-content/60">
                  <th>Product</th>
                  <th>Plan</th>
                  <th>Status</th>
                  <th class="text-right">Count</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={row <- stats.by_product_plan} class="hover:bg-base-200">
                  <td class="font-medium">{row.product}</td>
                  <td>{row.plan}</td>
                  <td>{row.status}</td>
                  <td class="text-right tabular-nums">{row.count}</td>
                </tr>
                <tr :if={stats.by_product_plan == []}>
                  <td colspan="4" class="text-center text-base-content/50">No data</td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>

        <.stats_section
          title="By Type (active + trialing + past_due)"
          cols="grid-cols-2 sm:grid-cols-3 lg:grid-cols-5"
        >
          <.stat_card
            :for={row <- stats.by_type}
            label={row.type |> to_string()}
            value={row.count}
          />
        </.stats_section>

        <section>
          <.section_heading>Internal (@santiment.net) vs External</.section_heading>
          <div class="grid grid-cols-1 lg:grid-cols-2 gap-3">
            <.user_segment_table
              title={"Internal · #{stats.internal_external.internal.total}"}
              rows={stats.internal_external.internal.by_status}
            />
            <.user_segment_table
              title={"External · #{stats.internal_external.external.total}"}
              rows={stats.internal_external.external.by_status}
            />
          </div>
        </section>

        <section>
          <.section_heading>Trialing</.section_heading>
          <div class="grid gap-2 grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 mb-3">
            <.stat_card label="Total Trialing" value={stats.trialing.total} />
            <.stat_card
              label="Ending in 3d"
              value={stats.trialing.ending_3d}
              accent={(stats.trialing.ending_3d > 0 && "text-warning") || nil}
            />
            <.stat_card label="Ending in 7d" value={stats.trialing.ending_7d} />
          </div>
          <div class="overflow-x-auto bg-base-100 border border-base-300 rounded">
            <table class="table table-sm">
              <thead>
                <tr class="text-base-content/60">
                  <th>Product</th>
                  <th>Plan</th>
                  <th class="text-right">Count</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={row <- stats.trialing.by_plan} class="hover:bg-base-200">
                  <td class="font-medium">{row.product}</td>
                  <td>{row.plan}</td>
                  <td class="text-right tabular-nums">{row.count}</td>
                </tr>
                <tr :if={stats.trialing.by_plan == []}>
                  <td colspan="3" class="text-center text-base-content/50">No trialing subs</td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>

        <section>
          <.section_heading>
            Scheduled Cancellations · {stats.scheduled_cancellations.total}
          </.section_heading>
          <div class="overflow-x-auto bg-base-100 border border-base-300 rounded">
            <table class="table table-sm">
              <thead>
                <tr class="text-base-content/60">
                  <th>Product</th>
                  <th>Plan</th>
                  <th class="text-right">Count</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={row <- stats.scheduled_cancellations.by_plan} class="hover:bg-base-200">
                  <td class="font-medium">{row.product}</td>
                  <td>{row.plan}</td>
                  <td class="text-right tabular-nums">{row.count}</td>
                </tr>
                <tr :if={stats.scheduled_cancellations.by_plan == []}>
                  <td colspan="3" class="text-center text-base-content/50">None scheduled</td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>

        <.stats_section title="Recent Activity" cols="grid-cols-2 sm:grid-cols-4">
          <.stat_card label="Created · 7d" value={stats.recent_activity.created_7d} />
          <.stat_card label="Created · 30d" value={stats.recent_activity.created_30d} />
          <.stat_card label="Canceled · 7d" value={stats.recent_activity.canceled_7d} />
          <.stat_card label="Canceled · 30d" value={stats.recent_activity.canceled_30d} />
        </.stats_section>

        <section>
          <.section_heading>Created in Last 30d · By Plan</.section_heading>
          <div class="overflow-x-auto bg-base-100 border border-base-300 rounded">
            <table class="table table-sm">
              <thead>
                <tr class="text-base-content/60">
                  <th>Product</th>
                  <th>Plan</th>
                  <th class="text-right">Count</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={row <- stats.recent_activity.created_by_plan_30d} class="hover:bg-base-200">
                  <td class="font-medium">{row.product}</td>
                  <td>{row.plan}</td>
                  <td class="text-right tabular-nums">{row.count}</td>
                </tr>
                <tr :if={stats.recent_activity.created_by_plan_30d == []}>
                  <td colspan="3" class="text-center text-base-content/50">No data</td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>

        <.discounts_section discounts={stats.discounts} />
      </.async_result>
    </div>
    """
  end

  attr(:title, :string, required: true)
  attr(:rows, :list, required: true)

  defp user_segment_table(assigns) do
    ~H"""
    <div class="bg-base-100 border border-base-300 rounded">
      <div class="px-3 py-2 border-b border-base-300 text-sm font-semibold">{@title}</div>
      <table class="table table-sm">
        <thead>
          <tr class="text-base-content/60">
            <th>Status</th>
            <th class="text-right">Count</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={row <- @rows} class="hover:bg-base-200">
            <td class="font-medium">{row.status}</td>
            <td class="text-right tabular-nums">{row.count}</td>
          </tr>
          <tr :if={@rows == []}>
            <td colspan="2" class="text-center text-base-content/50">No data</td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  attr(:discounts, :any, required: true)

  defp discounts_section(%{discounts: {:error, _}} = assigns) do
    ~H"""
    <section>
      <.section_heading>Discounts (Stripe)</.section_heading>
      <div class="alert alert-warning">
        Could not pull discount data from Stripe. The rest of the dashboard is from the local DB.
      </div>
    </section>
    """
  end

  defp discounts_section(%{discounts: {:ok, _}} = assigns) do
    assigns = assign(assigns, :d, elem(assigns.discounts, 1))

    ~H"""
    <section class="space-y-3">
      <.section_heading>Discounts (Stripe-applied, joined by stripe_id)</.section_heading>

      <div class="grid gap-2 grid-cols-2 sm:grid-cols-3 lg:grid-cols-5">
        <.stat_card label="Discounted Subs" value={@d.total} />
        <.stat_card label="Stripe Active Subs" value={@d.total_stripe_active} />
        <.stat_card label="Internal" value={@d.internal_count} />
        <.stat_card label="External" value={@d.external_count} />
        <.stat_card
          label="Expiring · 30d"
          value={@d.expiring_30d}
          accent={(@d.expiring_30d > 0 && "text-warning") || nil}
        />
        <.stat_card
          :for={{product, count} <- @d.by_product}
          label={"#{product} discounted"}
          value={count}
        />
        <.stat_card
          label="Drift · local only"
          value={@d.drift_local_only}
          accent={(@d.drift_local_only > 0 && "text-warning") || nil}
        />
        <.stat_card
          label="Drift · Stripe only"
          value={@d.drift_stripe_only}
          accent={(@d.drift_stripe_only > 0 && "text-warning") || nil}
        />
      </div>

      <div class="grid gap-3 grid-cols-1 lg:grid-cols-2">
        <div class="bg-base-100 border border-base-300 rounded">
          <div class="px-3 py-2 border-b border-base-300 text-sm font-semibold">
            % off distribution
          </div>
          <table class="table table-sm">
            <thead>
              <tr class="text-base-content/60">
                <th>% off</th>
                <th class="text-right">Subs</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={row <- @d.histogram} class="hover:bg-base-200">
                <td class="font-medium">{row.percent_off || "—"}</td>
                <td class="text-right tabular-nums">{row.count}</td>
              </tr>
              <tr :if={@d.histogram == []}>
                <td colspan="2" class="text-center text-base-content/50">No discounted subs</td>
              </tr>
            </tbody>
          </table>
        </div>

        <div class="bg-base-100 border border-base-300 rounded">
          <div class="px-3 py-2 border-b border-base-300 text-sm font-semibold">Top coupons</div>
          <table class="table table-sm">
            <thead>
              <tr class="text-base-content/60">
                <th>Coupon</th>
                <th>% off</th>
                <th class="text-right">Subs</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={row <- @d.top_coupons} class="hover:bg-base-200">
                <td class="font-medium">
                  {row.coupon_name || row.coupon_id || "—"}
                </td>
                <td>{row.percent_off || "—"}</td>
                <td class="text-right tabular-nums">{row.count}</td>
              </tr>
              <tr :if={@d.top_coupons == []}>
                <td colspan="3" class="text-center text-base-content/50">No coupons in use</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <div class="bg-base-100 border border-base-300 rounded">
        <div class="px-3 py-2 border-b border-base-300 text-sm font-semibold">By product × plan</div>
        <table class="table table-sm">
          <thead>
            <tr class="text-base-content/60">
              <th>Product</th>
              <th>Plan</th>
              <th class="text-right">Discounted Subs</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={row <- @d.by_plan} class="hover:bg-base-200">
              <td class="font-medium">{row.product}</td>
              <td>{row.plan}</td>
              <td class="text-right tabular-nums">{row.count}</td>
            </tr>
            <tr :if={@d.by_plan == []}>
              <td colspan="3" class="text-center text-base-content/50">No discounted subs</td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>
    """
  end

  defp loading_skeleton(assigns) do
    ~H"""
    <div class="space-y-4 animate-pulse">
      <div class="h-3 w-64 bg-base-300 rounded"></div>
      <div :for={_ <- 1..4} class="space-y-2">
        <div class="h-3 w-32 bg-base-300 rounded"></div>
        <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-2">
          <div :for={_ <- 1..5} class="h-8 bg-base-300 rounded"></div>
        </div>
      </div>
    </div>
    """
  end

  attr(:title, :string, required: true)
  attr(:cols, :string, required: true)
  slot(:inner_block, required: true)

  defp stats_section(assigns) do
    ~H"""
    <section>
      <.section_heading>{@title}</.section_heading>
      <div class={["grid gap-2", @cols]}>
        {render_slot(@inner_block)}
      </div>
    </section>
    """
  end

  slot(:inner_block, required: true)

  defp section_heading(assigns) do
    ~H"""
    <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/60 mb-2">
      {render_slot(@inner_block)}
    </h2>
    """
  end
end
