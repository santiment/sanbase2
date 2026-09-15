defmodule SanbaseWeb.Admin.CreditPaymentsLive do
  use SanbaseWeb, :live_view

  import SanbaseWeb.AdminLiveHelpers, only: [parse_int: 2]

  alias Sanbase.Billing.CreditPayments
  alias Sanbase.Billing.CreditPayments.{Store, SyncJob}

  @default_months_back 5
  @page_sizes [25, 50, 100, 250]

  def mount(_params, _session, socket) do
    if connected?(socket), do: SyncJob.subscribe()

    today = Date.utc_today()
    from = today |> Timex.shift(months: -@default_months_back) |> Timex.beginning_of_month()

    socket =
      socket
      |> assign(:page_title, "Credit Payments")
      |> assign(:from_date, from)
      |> assign(:to_date, today)
      |> assign(:granularity, :month)
      |> assign(:source_filter, :all)
      |> assign(:query, "")
      |> assign(:page, 1)
      |> assign(:page_size, 25)
      |> assign(:page_sizes, @page_sizes)
      |> assign(:lookup_identifier, "")
      |> assign(:ledger, nil)
      |> assign(:sync_job, SyncJob.get_state())
      |> load_report()

    {:ok, socket}
  end

  def handle_event("select_range", %{"from" => from, "to" => to}, socket) do
    socket =
      socket
      |> assign(:from_date, parse_date(from, socket.assigns.from_date))
      |> assign(:to_date, parse_date(to, socket.assigns.to_date))
      |> assign(:page, 1)
      |> load_report()

    {:noreply, socket}
  end

  def handle_event("preset", %{"months" => months}, socket) do
    today = Date.utc_today()
    months = parse_int(months, 1)

    from =
      case months do
        0 -> Timex.beginning_of_month(today)
        n -> today |> Timex.shift(months: -(n - 1)) |> Timex.beginning_of_month()
      end

    socket =
      socket
      |> assign(:from_date, from)
      |> assign(:to_date, today)
      |> assign(:page, 1)
      |> load_report()

    {:noreply, socket}
  end

  def handle_event("filter", params, socket) do
    socket =
      socket
      |> assign(:source_filter, CreditPayments.parse_source(params["source"]))
      |> assign(:query, params["query"] || "")
      |> assign(:granularity, CreditPayments.parse_granularity(params["granularity"]))
      |> assign(:page_size, parse_int(params["page_size"], socket.assigns.page_size))
      |> assign(:page, 1)

    {:noreply, socket}
  end

  def handle_event("page", %{"page" => page}, socket) do
    {:noreply, assign(socket, :page, parse_int(page, socket.assigns.page))}
  end

  def handle_event("refresh", _params, socket) do
    {:noreply, load_report(socket)}
  end

  def handle_event("resync", params, socket) do
    from = parse_date(params["from"] || "", socket.assigns.from_date)
    to = parse_date(params["to"] || "", socket.assigns.to_date)

    case SyncJob.start_job(from, to, socket.assigns.current_user.id) do
      :ok ->
        {:noreply, assign(socket, :sync_job, SyncJob.get_state())}

      {:error, :already_running} ->
        {:noreply, put_flash(socket, :error, "An import is already running")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not start the import: #{inspect(reason)}")}
    end
  end

  def handle_event("cancel_sync", _params, socket) do
    SyncJob.cancel()

    {:noreply, assign(socket, :sync_job, SyncJob.get_state())}
  end

  def handle_event("lookup", %{"identifier" => identifier}, socket) do
    identifier = String.trim(identifier)

    socket =
      socket
      |> assign(:lookup_identifier, identifier)
      |> load_ledger(identifier)

    {:noreply, socket}
  end

  def handle_event("clear_lookup", _params, socket) do
    {:noreply, socket |> assign(:lookup_identifier, "") |> assign(:ledger, nil)}
  end

  def handle_info({:sync_update, job_state}, socket) do
    socket = assign(socket, :sync_job, job_state)

    # The mirror only changes when the import finishes, so that is the one moment the
    # page has to read it again.
    socket = if job_state.status == :done, do: load_report(socket), else: socket

    {:noreply, socket}
  end

  defp load_report(socket) do
    from = socket.assigns.from_date
    to = socket.assigns.to_date

    assign_async(socket, :report, fn ->
      {:ok, %{report: Store.range_report(from, to)}}
    end)
  end

  defp load_ledger(socket, "") do
    assign(socket, :ledger, nil)
  end

  defp load_ledger(socket, identifier) do
    assign_async(socket, :ledger, fn ->
      case CreditPayments.resolve_customer_id(identifier) do
        nil ->
          {:error, "No stripe customer found for #{identifier}"}

        customer_id ->
          {:ok, %{ledger: CreditPayments.customer_ledger(customer_id)}}
      end
    end)
  end

  defp parse_date(value, fallback) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> fallback
    end
  end

  # ─── Derived data ────────────────────────────────────────────────────────

  defp filtered(report, assigns) do
    CreditPayments.filter_invoices(report.invoices,
      source: assigns.source_filter,
      query: assigns.query
    )
  end

  defp paginated(rows, page, page_size) do
    Enum.slice(rows, (page - 1) * page_size, page_size)
  end

  defp page_count(rows, page_size) do
    max(ceil(length(rows) / page_size), 1)
  end

  defp export_path(assigns, what) do
    ~p"/admin/credit_payments/export?#{[from: Date.to_iso8601(assigns.from_date), to: Date.to_iso8601(assigns.to_date), source: to_string(assigns.source_filter), query: assigns.query, what: what]}"
  end

  # ─── Formatting ──────────────────────────────────────────────────────────

  defp money(nil), do: "$0.00"

  defp money(cents) when is_integer(cents) do
    sign = if cents < 0, do: "-", else: ""
    cents = abs(cents)

    dollars =
      cents
      |> div(100)
      |> to_string()
      |> String.reverse()
      |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
      |> String.reverse()

    "#{sign}$#{dollars}.#{rem(cents, 100) |> to_string() |> String.pad_leading(2, "0")}"
  end

  defp format_date(nil), do: "-"
  defp format_date(dt), do: Calendar.strftime(dt, "%Y-%m-%d")

  defp format_datetime(nil), do: "-"
  defp format_datetime(dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")

  defp source_label(:san_burn), do: "SAN burn"
  defp source_label(:crypto), do: "Crypto"
  defp source_label(:wire), do: "Wire / bank"
  defp source_label(:other), do: "Unclassified"
  defp source_label(:unknown), do: "No note"
  defp source_label(other), do: to_string(other)

  defp source_badge_class(:san_burn), do: "badge-warning"
  defp source_badge_class(:crypto), do: "badge-success"
  defp source_badge_class(:wire), do: "badge-info"
  defp source_badge_class(_), do: "badge-ghost"

  # The note is written by hand in Stripe and is most often a block explorer link, so
  # make that link clickable. The note itself lives on the customer's balance ledger,
  # which has no page of its own - `stripe_customer_url/1` is as close as it gets.
  defp note_url(nil), do: nil

  defp note_url(description) do
    case Regex.run(~r{https?://\S+}, description) do
      [url] -> url
      _ -> nil
    end
  end

  defp sources_in_order(by_source) do
    [:crypto, :wire, :other, :san_burn, :unknown]
    |> Enum.map(&{&1, Map.get(by_source, &1, 0)})
    |> Enum.reject(fn {_source, amount} -> amount == 0 end)
  end

  # The customer is worth a link in every case: to the user record when we could match
  # one, and to Stripe when we could not - a bare `cus_...` string is a dead end.
  attr(:row, :map, required: true)

  defp customer_cell(assigns) do
    ~H"""
    <.link
      :if={@row.user_id}
      navigate={~p"/admin/generic/#{@row.user_id}?resource=users"}
      class="link link-primary"
      title={@row.customer}
    >
      {@row.email || @row.customer}
    </.link>

    <span :if={is_nil(@row.user_id)} class="flex flex-col">
      <span :if={@row.email} class="text-base-content/70">{@row.email}</span>
      <.link
        :if={@row.customer}
        href={CreditPayments.stripe_customer_url(@row.customer)}
        target="_blank"
        class="link text-xs font-mono"
        title="No Sanbase user matches this stripe customer - open it in Stripe"
      >
        {@row.customer}
      </.link>
    </span>
    """
  end

  defp sync_running?(job), do: job != nil and job.status == :running

  defp sync_phase_text(%{phase: :fetching}), do: "Reading invoices and ledgers from Stripe..."
  defp sync_phase_text(%{phase: :writing}), do: "Writing the imported rows..."
  defp sync_phase_text(_job), do: "Working..."

  defp coverage_text(gaps) do
    Enum.map_join(gaps, ", ", fn
      {from, from} -> Date.to_iso8601(from)
      {from, to} -> "#{Date.to_iso8601(from)} to #{Date.to_iso8601(to)}"
    end)
  end

  defp granularity_label(:day), do: "Day"
  defp granularity_label(:month), do: "Month"
  defp granularity_label(:year), do: "Year"
  defp granularity_label(:all), do: "Whole range"

  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-7xl mx-auto">
      <h1 class="text-3xl font-bold mb-2">Credit Payments</h1>
      <p class="text-sm text-base-content/60 mb-6">
        Invoices settled from the customer's Stripe credit balance - crypto payments and
        wire transfers - instead of by a card charge. These produce no Stripe charge, so
        they are missing from the charge-based revenue exports.
      </p>

      <%!-- ── Range ─────────────────────────────────────────────────── --%>
      <div class="card bg-base-100 border border-base-300 p-4 mb-4">
        <form id="range-form" phx-change="select_range" class="flex flex-wrap items-end gap-4">
          <fieldset class="fieldset">
            <legend class="fieldset-legend">From</legend>
            <input type="date" name="from" value={@from_date} class="input input-sm" />
          </fieldset>

          <fieldset class="fieldset">
            <legend class="fieldset-legend">To</legend>
            <input type="date" name="to" value={@to_date} class="input input-sm" />
          </fieldset>

          <div class="flex items-center gap-2">
            <button type="button" phx-click="preset" phx-value-months="0" class="btn btn-xs btn-soft">
              This month
            </button>
            <button type="button" phx-click="preset" phx-value-months="3" class="btn btn-xs btn-soft">
              3 months
            </button>
            <button type="button" phx-click="preset" phx-value-months="6" class="btn btn-xs btn-soft">
              6 months
            </button>
            <button type="button" phx-click="preset" phx-value-months="12" class="btn btn-xs btn-soft">
              12 months
            </button>
            <button type="button" phx-click="refresh" class="btn btn-xs btn-soft">
              Refresh
            </button>
          </div>
        </form>
      </div>

      <%!-- ── Import state ──────────────────────────────────────────── --%>
      <div class="card bg-base-100 border border-base-300 p-4 mb-6">
        <div class="flex flex-wrap items-center justify-between gap-3">
          <div class="text-sm">
            <span class="text-base-content/60">The table reads a local mirror of Stripe.</span>
            <span :if={@sync_job.status != :running} class="text-base-content/60">
              Re-import the selected range to pick up anything an earlier import skipped.
            </span>
          </div>

          <div class="flex items-center gap-2">
            <button
              phx-click="resync"
              disabled={sync_running?(@sync_job)}
              class="btn btn-sm btn-primary"
            >
              Re-import from Stripe
            </button>
            <button
              :if={sync_running?(@sync_job)}
              phx-click="cancel_sync"
              class="btn btn-sm btn-soft btn-error"
            >
              Stop watching
            </button>
          </div>
        </div>

        <div :if={sync_running?(@sync_job)} class="mt-3">
          <div class="flex items-center gap-3">
            <span class="loading loading-spinner loading-sm"></span>
            <span class="text-sm">
              {sync_phase_text(@sync_job)} ({@sync_job.from_date} to {@sync_job.to_date})
            </span>
          </div>
          <progress class="progress progress-primary w-full mt-2"></progress>
        </div>

        <div
          :if={@sync_job.status == :done && @sync_job.result}
          role="alert"
          class="alert alert-success mt-3"
        >
          <span>
            Imported {@sync_job.result.invoices_upserted} invoice(s) and {@sync_job.result.grants_upserted} ledger entr(ies) from {@sync_job.result.customers_scanned} customer(s).
          </span>
        </div>

        <div :if={@sync_job.status == :failed} role="alert" class="alert alert-error mt-3">
          <span>The import failed: {@sync_job.error}</span>
        </div>
      </div>

      <.async_result :let={report} assign={@report}>
        <:loading>
          <div class="flex items-center gap-3 py-10">
            <span class="loading loading-spinner loading-md"></span>
            <span class="text-sm text-base-content/70">
              Reading invoices and customer balance ledgers from Stripe...
            </span>
          </div>
        </:loading>

        <:failed :let={reason}>
          <div role="alert" class="alert alert-error mb-6">
            <span>Failed to load the report: {inspect(reason)}</span>
          </div>
        </:failed>

        <div :if={report.coverage != []} role="alert" class="alert alert-warning mb-4">
          <span>
            Never imported: {coverage_text(report.coverage)}. The numbers below leave those
            days out - re-import the range to fill them in.
          </span>
        </div>

        <div class="text-xs text-base-content/60 mb-4">
          Mirror last updated: {format_datetime(report.last_synced_at)}
        </div>

        <%!-- ── Summary ───────────────────────────────────────────────── --%>
        <div class="grid grid-cols-2 md:grid-cols-4 gap-4 mb-4">
          <div class="card bg-base-100 border border-base-300 p-4">
            <div class="text-xs uppercase text-base-content/60">Paid from credit</div>
            <div class="text-2xl font-bold">{money(report.totals.credit_applied)}</div>
            <div class="text-xs text-base-content/60">
              {report.totals.invoice_count} invoice(s)
            </div>
          </div>

          <div class="card bg-base-100 border border-base-300 p-4">
            <div class="text-xs uppercase text-base-content/60">Credit added</div>
            <div class="text-2xl font-bold">{money(report.totals.credit_granted)}</div>
            <div class="text-xs text-base-content/60">
              {report.totals.grant_count} adjustment(s)
            </div>
          </div>

          <div class="card bg-base-100 border border-base-300 p-4">
            <div class="text-xs uppercase text-base-content/60">Card-paid remainder</div>
            <div class="text-2xl font-bold">{money(report.totals.card_paid)}</div>
            <div class="text-xs text-base-content/60">
              on the same invoices, of {money(report.totals.invoiced_total)} invoiced
            </div>
          </div>

          <div class="card bg-base-100 border border-base-300 p-4">
            <div class="text-xs uppercase text-base-content/60">Settled out of band</div>
            <div class="text-2xl font-bold">{money(report.totals.out_of_band_total)}</div>
            <div class="text-xs text-base-content/60">
              {report.totals.out_of_band_count} invoice(s), {report.totals.unmatched_note_count} without a note
            </div>
          </div>
        </div>

        <div class="flex flex-col gap-2 mb-6">
          <div
            :if={sources_in_order(report.totals.credit_applied_by_source) != []}
            class="flex flex-wrap items-center gap-3"
          >
            <span class="text-sm text-base-content/60">Invoices paid from credit, by source:</span>
            <span
              :for={{source, amount} <- sources_in_order(report.totals.credit_applied_by_source)}
              class={["badge badge-sm", source_badge_class(source)]}
            >
              {source_label(source)}: {money(amount)}
            </span>
          </div>

          <div
            :if={sources_in_order(report.totals.by_source) != []}
            class="flex flex-wrap items-center gap-3"
          >
            <span class="text-sm text-base-content/60">Credit added, by source:</span>
            <span
              :for={{source, amount} <- sources_in_order(report.totals.by_source)}
              class={["badge badge-sm", source_badge_class(source)]}
            >
              {source_label(source)}: {money(amount)}
            </span>
          </div>
        </div>

        <%!-- ── Filters ───────────────────────────────────────────────── --%>
        <div class="card bg-base-100 border border-base-300 p-4 mb-6">
          <form id="filter-form" phx-change="filter" class="flex flex-wrap items-end gap-4">
            <fieldset class="fieldset">
              <legend class="fieldset-legend">Search</legend>
              <input
                type="text"
                name="query"
                value={@query}
                placeholder="email, invoice number, note"
                phx-debounce="300"
                class="input input-sm w-72"
              />
            </fieldset>

            <fieldset class="fieldset">
              <legend class="fieldset-legend">Source</legend>
              <select name="source" class="select select-sm w-40">
                <option
                  :for={source <- [:all, :crypto, :wire, :san_burn, :other, :unknown]}
                  value={source}
                  selected={source == @source_filter}
                >
                  {if source == :all, do: "All sources", else: source_label(source)}
                </option>
              </select>
            </fieldset>

            <fieldset class="fieldset">
              <legend class="fieldset-legend">Aggregate by</legend>
              <select name="granularity" class="select select-sm w-36">
                <option
                  :for={granularity <- [:day, :month, :year, :all]}
                  value={granularity}
                  selected={granularity == @granularity}
                >
                  {granularity_label(granularity)}
                </option>
              </select>
            </fieldset>

            <fieldset class="fieldset">
              <legend class="fieldset-legend">Rows per page</legend>
              <select name="page_size" class="select select-sm w-28">
                <option :for={size <- @page_sizes} value={size} selected={size == @page_size}>
                  {size}
                </option>
              </select>
            </fieldset>

            <div class="flex items-center gap-2">
              <.link href={export_path(assigns, "invoices")} class="btn btn-sm btn-primary">
                Download CSV
              </.link>
              <.link href={export_path(assigns, "grants")} class="btn btn-sm btn-soft">
                Credits CSV
              </.link>
            </div>
          </form>
        </div>

        <%!-- ── Aggregation ───────────────────────────────────────────── --%>
        <h2 class="text-xl font-semibold mb-2">
          Totals by {String.downcase(granularity_label(@granularity))}
        </h2>

        <div class="rounded-box border border-base-300 overflow-x-auto mb-8">
          <table class="table table-zebra table-sm">
            <thead>
              <tr>
                <th>{granularity_label(@granularity)}</th>
                <th class="text-right">Invoices</th>
                <th class="text-right">Invoiced</th>
                <th class="text-right">Paid by credit</th>
                <th class="text-right">Paid by card</th>
                <th class="text-right">Out of band</th>
                <th>By source</th>
              </tr>
            </thead>
            <tbody>
              <tr :if={filtered(report, assigns) == []}>
                <td colspan="7" class="text-center text-base-content/60 py-6">
                  Nothing to aggregate for this range and filter.
                </td>
              </tr>
              <tr :for={bucket <- CreditPayments.aggregate(filtered(report, assigns), @granularity)}>
                <td class="font-medium whitespace-nowrap">{bucket.label}</td>
                <td class="text-right">{bucket.invoice_count}</td>
                <td class="text-right text-base-content/70">{money(bucket.total)}</td>
                <td class="text-right font-medium">{money(bucket.credit_applied)}</td>
                <td class="text-right text-base-content/70">{money(bucket.card_paid)}</td>
                <td class="text-right text-base-content/70">{money(bucket.out_of_band)}</td>
                <td>
                  <div class="flex flex-wrap gap-1">
                    <span
                      :for={{source, amount} <- sources_in_order(bucket.by_source)}
                      class={["badge badge-xs", source_badge_class(source)]}
                    >
                      {source_label(source)}: {money(amount)}
                    </span>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <%!-- ── Credit-settled invoices ───────────────────────────────── --%>
        <h2 class="text-xl font-semibold mb-2">Invoices settled from credit</h2>
        <p class="text-sm text-base-content/60 mb-2">
          The source note is the internal note of the credit adjustment that funded the
          invoice, matched to it by time. "No note" means credit paid the invoice but no
          adjustment note was found for that customer.
        </p>

        <div class="rounded-box border border-base-300 overflow-x-auto mb-2">
          <table class="table table-zebra table-sm">
            <thead>
              <tr>
                <th>#</th>
                <th>Invoice</th>
                <th>Customer</th>
                <th>Date</th>
                <th class="text-right">Total</th>
                <th class="text-right">Paid by credit</th>
                <th class="text-right">Paid by card</th>
                <th>Source note</th>
              </tr>
            </thead>
            <tbody>
              <tr :if={filtered(report, assigns) == []}>
                <td colspan="8" class="text-center text-base-content/60 py-6">
                  No invoice was settled from credit in this range.
                </td>
              </tr>
              <tr :for={
                {invoice, index} <-
                  report
                  |> filtered(assigns)
                  |> paginated(@page, @page_size)
                  |> Enum.with_index((@page - 1) * @page_size + 1)
              }>
                <td class="text-base-content/60">{index}</td>
                <td>
                  <.link
                    href={CreditPayments.stripe_invoice_url(invoice.id)}
                    target="_blank"
                    class="link link-primary font-mono text-xs"
                    title="Open the invoice in Stripe"
                  >
                    {invoice.number || invoice.id}
                  </.link>
                </td>
                <td>
                  <.customer_cell row={invoice} />
                </td>
                <td class="whitespace-nowrap">{format_date(invoice.created)}</td>
                <td class="text-right">{money(invoice.total)}</td>
                <td class="text-right font-medium">{money(invoice.credit_applied)}</td>
                <td class="text-right text-base-content/70">{money(invoice.amount_paid)}</td>
                <td class="max-w-md">
                  <div class="flex items-center gap-2">
                    <span class={["badge badge-xs", source_badge_class(invoice.source)]}>
                      {source_label(invoice.source)}
                    </span>
                    <span :if={invoice.paid_out_of_band} class="badge badge-xs badge-info">
                      out of band
                    </span>
                    <.link
                      :if={invoice.customer}
                      href={CreditPayments.stripe_customer_url(invoice.customer)}
                      target="_blank"
                      class="link text-xs"
                      title="Open the credit balance and its internal note in Stripe"
                    >
                      note in Stripe
                    </.link>
                  </div>
                  <.link
                    :if={note_url(invoice.source_note)}
                    href={note_url(invoice.source_note)}
                    target="_blank"
                    class="link link-primary break-all text-xs"
                  >
                    {invoice.source_note}
                  </.link>
                  <span
                    :if={invoice.source_note && is_nil(note_url(invoice.source_note))}
                    class="text-xs text-base-content/70 break-all"
                  >
                    {invoice.source_note}
                  </span>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <%!-- ── Pagination ────────────────────────────────────────────── --%>
        <div class="flex items-center justify-between mb-8">
          <span class="text-sm text-base-content/60">
            {length(filtered(report, assigns))} invoice(s), page {@page} of {page_count(
              filtered(report, assigns),
              @page_size
            )}
          </span>

          <div class="join">
            <button
              phx-click="page"
              phx-value-page={@page - 1}
              disabled={@page <= 1}
              class="join-item btn btn-sm"
            >
              Previous
            </button>
            <button
              phx-click="page"
              phx-value-page={@page + 1}
              disabled={@page >= page_count(filtered(report, assigns), @page_size)}
              class="join-item btn btn-sm"
            >
              Next
            </button>
          </div>
        </div>

        <%!-- ── Credit grants ─────────────────────────────────────────── --%>
        <h2 class="text-xl font-semibold mb-2">Credit added in this range</h2>
        <p class="text-sm text-base-content/60 mb-2">
          The internal note is the only record of how the money arrived. Only customers with
          balance activity on an invoice in this range are scanned ({report.scanned_customers} customer(s)) -
          use the lookup below for anyone else.
        </p>

        <div class="rounded-box border border-base-300 overflow-x-auto mb-8">
          <table class="table table-zebra table-sm">
            <thead>
              <tr>
                <th>Date</th>
                <th>Customer</th>
                <th class="text-right">Amount</th>
                <th>Source</th>
                <th>Internal note</th>
              </tr>
            </thead>
            <tbody>
              <tr :if={report.grants == []}>
                <td colspan="5" class="text-center text-base-content/60 py-6">
                  No credit was added in this range.
                </td>
              </tr>
              <tr :for={grant <- report.grants}>
                <td class="whitespace-nowrap">{format_date(grant.created)}</td>
                <td>
                  <.customer_cell row={grant} />
                </td>
                <td class="text-right font-medium">{money(grant.amount)}</td>
                <td>
                  <div class="flex items-center gap-2">
                    <span class={["badge badge-xs", source_badge_class(grant.source)]}>
                      {source_label(grant.source)}
                    </span>
                    <.link
                      :if={grant.customer}
                      href={CreditPayments.stripe_customer_url(grant.customer)}
                      target="_blank"
                      class="link text-xs"
                      title="Open the credit balance and its internal note in Stripe"
                    >
                      in Stripe
                    </.link>
                  </div>
                </td>
                <td class="max-w-md">
                  <.link
                    :if={note_url(grant.description)}
                    href={note_url(grant.description)}
                    target="_blank"
                    class="link link-primary break-all text-xs"
                  >
                    {grant.description}
                  </.link>
                  <span
                    :if={is_nil(note_url(grant.description))}
                    class="text-xs text-base-content/70 break-all"
                  >
                    {grant.description || "-"}
                  </span>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </.async_result>

      <%!-- ── Single customer ledger ────────────────────────────────── --%>
      <h2 class="text-xl font-semibold mb-2">Customer balance ledger</h2>
      <p class="text-sm text-base-content/60 mb-2">
        The full Stripe balance history of one customer, including credit that has not been
        applied to any invoice yet.
      </p>

      <form id="lookup-form" phx-submit="lookup" class="flex items-end gap-3 mb-4">
        <fieldset class="fieldset">
          <legend class="fieldset-legend">Email, user id or stripe customer id</legend>
          <input
            type="text"
            name="identifier"
            value={@lookup_identifier}
            placeholder="customer@example.com, 12345 or cus_..."
            class="input input-sm w-96"
          />
        </fieldset>
        <button type="submit" class="btn btn-sm btn-primary">Look up</button>
        <button :if={@ledger} type="button" phx-click="clear_lookup" class="btn btn-sm btn-soft">
          Clear
        </button>
      </form>

      <.async_result :let={ledger} :if={@ledger} assign={@ledger}>
        <:loading>
          <div class="flex items-center gap-3 py-4">
            <span class="loading loading-spinner loading-sm"></span>
            <span class="text-sm text-base-content/70">Reading the customer ledger...</span>
          </div>
        </:loading>

        <:failed :let={reason}>
          <div role="alert" class="alert alert-warning mb-6">
            <span>{if is_binary(reason), do: reason, else: inspect(reason)}</span>
          </div>
        </:failed>

        <div class="rounded-box border border-base-300 overflow-x-auto mb-8">
          <table class="table table-zebra table-sm">
            <thead>
              <tr>
                <th>Date</th>
                <th>Type</th>
                <th class="text-right">Amount</th>
                <th>Source</th>
                <th>Internal note</th>
                <th>Invoice</th>
              </tr>
            </thead>
            <tbody>
              <tr :if={ledger == []}>
                <td colspan="6" class="text-center text-base-content/60 py-6">
                  This customer has no balance transactions.
                </td>
              </tr>
              <tr :for={entry <- ledger}>
                <td class="whitespace-nowrap">{format_datetime(entry.created)}</td>
                <td class="text-base-content/70">{entry.type}</td>
                <td class="text-right font-medium">{money(entry.amount)}</td>
                <td>
                  <span
                    :if={entry.type == "adjustment"}
                    class={["badge badge-sm", source_badge_class(entry.source)]}
                  >
                    {source_label(entry.source)}
                  </span>
                </td>
                <td class="max-w-md text-xs text-base-content/70 break-all">
                  {entry.description || "-"}
                </td>
                <td class="text-xs">
                  <.link
                    :if={entry.invoice}
                    href={CreditPayments.stripe_invoice_url(entry.invoice)}
                    target="_blank"
                    class="link link-primary font-mono"
                  >
                    {entry.invoice}
                  </.link>
                  <span :if={is_nil(entry.invoice)} class="text-base-content/60">-</span>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </.async_result>
    </div>
    """
  end
end
