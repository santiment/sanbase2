defmodule SanbaseWeb.Admin.BundleOfferingLive do
  @moduledoc ~s"""
  Activate / deactivate SanAPI self-serve plan groups.

  * Bundle / new plans — toggles `is_private` on `BUNDLE*`, `INSTITUTIONAL*` and
    `ENTERPRISE*`. One switch for the whole offering.
  * Business plans — toggles `is_deprecated` on `BUSINESS_PRO` / `BUSINESS_MAX`.
    That is the only field the pricing page reads; `is_private` is deliberately
    left alone.
  """

  use SanbaseWeb, :live_view

  alias Sanbase.Billing.Plan.SaleControls

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Plan sale controls")
     |> load()}
  end

  @impl true
  def handle_event("activate_bundle", _params, socket) do
    {:ok, ids} = SaleControls.activate_bundle_plans()

    {:noreply,
     socket
     |> put_flash(:info, "Activated bundle/new plans (#{length(ids)} rows).")
     |> load()}
  end

  def handle_event("deactivate_bundle", _params, socket) do
    {:ok, ids} = SaleControls.deactivate_bundle_plans()

    {:noreply,
     socket
     |> put_flash(
       :info,
       "Deactivated bundle/new plans (#{length(ids)} rows). Team can still preview."
     )
     |> load()}
  end

  def handle_event("activate_business", _params, socket) do
    {:ok, ids} = SaleControls.activate_business_plans()

    {:noreply,
     socket
     |> put_flash(:info, "Activated Business Pro/Max for sale (#{length(ids)} rows).")
     |> load()}
  end

  def handle_event("deactivate_business", _params, socket) do
    {:ok, ids} = SaleControls.deactivate_business_plans()

    {:noreply,
     socket
     |> put_flash(
       :info,
       "Deactivated Business Pro/Max for new sale (#{length(ids)} rows). Existing subscribers keep access."
     )
     |> load()}
  end

  def handle_event("refresh", _params, socket) do
    {:noreply, load(socket)}
  end

  defp load(socket) do
    status = SaleControls.status()

    socket
    |> assign(:bundle_active?, status.bundle_plans_active?)
    |> assign(:business_active?, status.business_plans_active?)
    |> assign(:bundle_count, length(status.bundle_plan_ids))
    |> assign(:business_count, length(status.business_plan_ids))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col items-start justify-start p-4 min-h-screen bg-gray-100">
      <div class="bg-white rounded-lg shadow-sm w-full max-w-3xl p-6 space-y-8">
        <div class="flex items-center justify-between gap-4">
          <h1 class="text-2xl font-bold">Plan sale controls</h1>
          <button
            id="plan-sale-refresh"
            type="button"
            phx-click="refresh"
            class="px-3 py-1 text-sm rounded bg-gray-200 hover:bg-gray-300"
          >
            Refresh
          </button>
        </div>

        <section id="bundle-plan-controls" class="space-y-3 border rounded p-4">
          <h2 class="text-lg font-semibold">Bundle / new plans</h2>
          <p class="text-sm text-gray-600">
            `BUNDLE*`, `INSTITUTIONAL*` and `ENTERPRISE*` — toggles <code>is_private</code>.
            One switch for the whole offering, so activating also puts Institutional
            ($799/mo · $9,500/yr) and Enterprise ($19,999/yr) on self-serve sale.
            Deactivated = hidden from public catalog; Santiment team can still preview and subscribe.
          </p>
          <p class="text-sm">
            Status:
            <span class="font-semibold">
              {if @bundle_active?, do: "ACTIVE", else: "DEACTIVATED"}
            </span>
            ({@bundle_count} plan rows)
          </p>
          <div class="flex flex-wrap gap-3">
            <button
              id="activate-bundle-plans"
              type="button"
              phx-click="activate_bundle"
              data-confirm="Activate bundle/new plans for self-serve (set is_private=false)?"
              class="px-4 py-2 rounded bg-blue-600 text-white hover:bg-blue-700 disabled:opacity-40"
              disabled={@bundle_active?}
            >
              Activate bundle plans
            </button>
            <button
              id="deactivate-bundle-plans"
              type="button"
              phx-click="deactivate_bundle"
              data-confirm="Deactivate bundle/new plans (set is_private=true)?"
              class="px-4 py-2 rounded bg-gray-700 text-white hover:bg-gray-800 disabled:opacity-40"
              disabled={not @bundle_active?}
            >
              Deactivate bundle plans
            </button>
          </div>
        </section>

        <section id="business-plan-controls" class="space-y-3 border rounded p-4">
          <h2 class="text-lg font-semibold">Business plans</h2>
          <p class="text-sm text-gray-600">
            `BUSINESS_PRO` / `BUSINESS_MAX` — toggles <code>is_deprecated</code>, the only
            field the pricing page reads.
            Deactivated = not for new sale; existing subscribers keep access.
          </p>
          <p class="text-sm">
            Status:
            <span class="font-semibold">
              {if @business_active?, do: "ACTIVE", else: "DEACTIVATED"}
            </span>
            ({@business_count} plan rows)
          </p>
          <div class="flex flex-wrap gap-3">
            <button
              id="activate-business-plans"
              type="button"
              phx-click="activate_business"
              data-confirm="Activate Business Pro/Max for sale (clear is_deprecated)?"
              class="px-4 py-2 rounded bg-blue-600 text-white hover:bg-blue-700 disabled:opacity-40"
              disabled={@business_active?}
            >
              Activate business plans
            </button>
            <button
              id="deactivate-business-plans"
              type="button"
              phx-click="deactivate_business"
              data-confirm="Withdraw Business Pro/Max from sale (set is_deprecated)?"
              class="px-4 py-2 rounded bg-gray-700 text-white hover:bg-gray-800 disabled:opacity-40"
              disabled={not @business_active?}
            >
              Deactivate business plans
            </button>
          </div>
        </section>
      </div>
    </div>
    """
  end
end
