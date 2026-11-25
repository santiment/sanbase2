defmodule SanbaseWeb.Admin.BusinessClientLive do
  @moduledoc """
  One business client: the computed numbers, the invoices behind them, the manual
  health log and the business yes/no override.

  Viewing needs any Admin Panel role; adding and resolving log entries and changing
  the override need Editor. The checks run in the event handlers too, so a hidden
  button is not the only guard.
  """
  use SanbaseWeb, :live_view

  import SanbaseWeb.Admin.BusinessClientsLive,
    only: [
      money: 1,
      money_exact: 1,
      format_number: 1,
      format_date: 1,
      format_datetime: 1,
      tenure: 3,
      renewal_highlight?: 3,
      activity_source: 1,
      severity_label: 1,
      status_badge: 1,
      risk_level: 1,
      reason_badge: 1,
      note_mark: 1,
      formula_notes: 1,
      stripe_customer_link: 1,
      paid_by_mix: 1,
      paid_by_label: 1,
      paid_by_badge_class: 1
    ]

  alias Sanbase.Admin.Permissions
  alias Sanbase.Billing.BusinessClients
  alias Sanbase.Billing.BusinessClients.{ClientUsage, LogEntry, Override, PlanLimit}
  alias Sanbase.Billing.CreditPayments

  @impl true
  def mount(%{"user_id" => user_id}, _session, socket) do
    case Integer.parse(user_id) do
      {user_id, ""} ->
        settings = BusinessClients.settings()

        socket =
          socket
          |> assign(:page_title, "Business Client")
          |> assign(:user_id, user_id)
          |> assign(:today, Date.utc_today())
          |> assign(:settings, settings)
          |> assign(:notes, BusinessClients.formula_notes(settings))
          |> assign(:notes_open, false)
          |> assign_entry_form(BusinessClients.change_entry(%{}))
          |> assign(:override_form, to_form(%{"business" => "true", "note" => ""}, as: :override))
          |> load_entries()
          |> load_override()
          |> load_detail()
          |> load_usage()

        {:ok, socket}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Invalid user id")
         |> push_navigate(to: ~p"/admin/business_clients")}
    end
  end

  # ─── Events ──────────────────────────────────────────────────────────────

  @impl true
  def handle_event("toggle_section", %{"section" => "notes"}, socket) do
    {:noreply, assign(socket, :notes_open, !socket.assigns.notes_open)}
  end

  def handle_event("toggle_section", _params, socket), do: {:noreply, socket}

  # An asterisk opens the formula notes; the link's own anchor jumps to the note.
  def handle_event("open_notes", _params, socket) do
    {:noreply, assign(socket, :notes_open, true)}
  end

  def handle_event("validate_entry", %{"entry" => params}, socket) do
    changeset = params |> BusinessClients.change_entry() |> Map.put(:action, :validate)
    {:noreply, assign_entry_form(socket, changeset)}
  end

  def handle_event("add_entry", %{"entry" => params}, socket) do
    with_edit_permission(socket, fn ->
      %{user_id: user_id, current_user: current_user} = socket.assigns

      case BusinessClients.create_entry(user_id, current_user.id, params) do
        {:ok, _entry} ->
          socket
          |> assign_entry_form(BusinessClients.change_entry(%{}))
          |> put_flash(:info, "Entry added")
          |> load_entries()
          |> load_detail()

        {:error, changeset} ->
          assign_entry_form(socket, Map.put(changeset, :action, :insert))
      end
    end)
  end

  def handle_event("resolve_entry", %{"id" => id}, socket) do
    with_edit_permission(socket, fn -> resolve_own_entry(socket, parse_id(id)) end)
  end

  def handle_event("set_override", %{"override" => params}, socket) do
    with_edit_permission(socket, fn ->
      %{user_id: user_id, current_user: current_user} = socket.assigns
      business? = params["business"] == "true"
      note = params["note"] |> to_string() |> String.trim()
      note = if note == "", do: nil, else: note

      case BusinessClients.set_override(user_id, business?, current_user.id, note) do
        {:ok, _override} ->
          socket
          |> put_flash(:info, "Override saved")
          |> load_override()
          |> load_detail()

        {:error, _changeset} ->
          put_flash(socket, :error, "Could not save the override")
      end
    end)
  end

  def handle_event("clear_override", _params, socket) do
    with_edit_permission(socket, fn ->
      :ok = BusinessClients.clear_override(socket.assigns.user_id)

      socket
      |> put_flash(:info, "Override cleared - the email domain rule applies again")
      |> load_override()
      |> load_detail()
    end)
  end

  # Only this client's entries can be resolved from this page.
  defp resolve_own_entry(socket, entry_id) do
    with true <- MapSet.member?(socket.assigns.entry_ids, entry_id),
         {:ok, _entry} <- BusinessClients.resolve_entry(entry_id, socket.assigns.current_user.id) do
      socket
      |> put_flash(:info, "Entry resolved")
      |> load_entries()
      |> load_detail()
    else
      false -> put_flash(socket, :error, "No such entry for this client")
      {:error, _reason} -> put_flash(socket, :error, "Could not resolve the entry")
    end
  end

  defp with_edit_permission(socket, fun) do
    if can_edit?(socket.assigns) do
      {:noreply, fun.()}
    else
      {:noreply, put_flash(socket, :error, "This needs the Admin Panel Editor role")}
    end
  end

  # ─── Loading ─────────────────────────────────────────────────────────────

  defp load_detail(socket) do
    user_id = socket.assigns.user_id

    assign_async(socket, :detail, fn ->
      {:ok, %{detail: BusinessClients.client_detail(user_id)}}
    end)
  end

  # What the client does with the product, read once per visit: the API, the web app
  # and what they built, side by side so one slow source does not hold the others.
  defp load_usage(socket) do
    %{user_id: user_id, today: today} = socket.assigns

    assign_async(socket, :usage, fn ->
      [api, web, creations] =
        [
          fn -> ClientUsage.api(user_id, today) end,
          fn -> ClientUsage.web(user_id, today) end,
          fn -> ClientUsage.creations(user_id, today) end
        ]
        |> Enum.map(&Task.async/1)
        |> Task.await_many(30_000)

      {:ok, %{usage: %{api: api, web: web, creations: creations}}}
    end)
  end

  defp load_entries(socket) do
    entries = BusinessClients.list_entries(socket.assigns.user_id)

    socket
    |> assign(:entry_ids, MapSet.new(entries, & &1.id))
    |> assign(:entries_count, length(entries))
    |> assign(:open_entries_count, Enum.count(entries, &is_nil(&1.resolved_at)))
    |> stream(:entries, entries, reset: true)
  end

  defp load_override(socket) do
    override =
      Override
      |> Sanbase.Repo.get_by(user_id: socket.assigns.user_id)
      |> Sanbase.Repo.preload(:set_by)

    assign(socket, :override, override)
  end

  defp assign_entry_form(socket, changeset) do
    assign(socket, :entry_form, to_form(changeset, as: :entry))
  end

  defp parse_id(id) when is_integer(id), do: id

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> int
      _ -> nil
    end
  end

  # ─── Helpers ─────────────────────────────────────────────────────────────

  defp can_edit?(assigns),
    do: Permissions.can?(:edit, roles: assigns[:current_user_role_names] || [])

  defp severity_disabled?(form, settings) do
    form[:type].value in settings.types_without_severity
  end

  # The override matters only where the email domain decides: a business plan always
  # counts, so its clients get no override control.
  defp override_applies?(nil, _override), do: true
  defp override_applies?(%{business_reason: :plan}, nil), do: false
  defp override_applies?(_client, _override), do: true

  defp change_label(0, 0), do: "-"
  defp change_label(_current, 0), do: "new"
  defp change_label(current, previous), do: "#{round((current - previous) * 100 / previous)}%"

  defp change_class(current, previous) when previous > 0 and current <= previous * 0.5,
    do: "text-error"

  defp change_class(current, previous) when previous > 0 and current >= previous * 1.5,
    do: "text-success"

  defp change_class(_current, _previous), do: "text-base-content/60"

  # Queries the client relied on before and dropped: at least 2% of the earlier calls,
  # down by 90% or more.
  defp stopped_queries(%{queries: queries, calls: %{previous: total}}) when total > 0 do
    queries
    |> Enum.filter(&(&1.previous >= total * 0.02 and &1.current <= &1.previous * 0.1))
    |> Enum.sort_by(& &1.previous, :desc)
    |> Enum.take(8)
  end

  defp stopped_queries(_api), do: []

  defp top(rows, count), do: rows |> Enum.filter(&(&1.current > 0)) |> Enum.take(count)

  defp at_risk?(%{risk_level: level}), do: level in [:at_risk, :high_risk]
  defp at_risk?(_client), do: false

  defp limit_label(:unlimited), do: "no limit"
  defp limit_label(nil), do: "unknown"
  defp limit_label(limit), do: "#{format_number(limit)} calls a month"

  defp month_label(date), do: Calendar.strftime(date, "%b %Y")

  defp percent(share), do: PlanLimit.percent(share)

  defp user_label(nil), do: "-"
  defp user_label(user), do: user.email || user.username || "user ##{user.id}"

  defp severity_badge_class("high_risk"), do: "badge-error"
  defp severity_badge_class("at_risk"), do: "badge-warning"
  defp severity_badge_class(_), do: "badge-ghost"

  defp invoice_status_class("paid"), do: "badge-success badge-soft"
  defp invoice_status_class("open"), do: "badge-warning badge-soft"
  defp invoice_status_class("uncollectible"), do: "badge-error badge-soft"
  defp invoice_status_class(_), do: "badge-ghost"

  defp source_label(nil), do: "-"
  defp source_label(source) when is_atom(source), do: paid_by_label(source)
  defp source_label(source), do: to_string(source)

  defp source_class(source) when is_atom(source), do: paid_by_badge_class(source)
  defp source_class(_source), do: "badge-ghost"

  # ─── Render ──────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-7xl mx-auto">
      <.link
        navigate={~p"/admin/business_clients"}
        id="back-to-clients"
        class="inline-flex items-center gap-1 text-sm link link-hover text-base-content/60 mb-2"
      >
        <.icon name="hero-arrow-left" class="w-4 h-4" /> Business Clients
      </.link>

      <.async_result :let={detail} assign={@detail}>
        <:loading>
          <div class="flex items-center gap-3 py-10">
            <span class="loading loading-spinner loading-md"></span>
            <span class="text-sm text-base-content/70">Loading the client...</span>
          </div>
        </:loading>

        <:failed :let={reason}>
          <div role="alert" class="alert alert-error mb-6">
            <span>Failed to load the client: {inspect(reason)}</span>
          </div>
        </:failed>

        <div class="flex flex-wrap items-baseline gap-3 mb-1">
          <h1 id="client-title" class="text-3xl font-bold break-all">{user_label(detail.user)}</h1>
          <.reason_badge
            :if={detail.client}
            reason={detail.client.business_reason}
            override={detail.client.override}
          />
          <.status_badge :if={detail.client} status={detail.client.manual_status} />
        </div>
        <div class="text-sm text-base-content/60 mb-6 flex flex-wrap gap-x-4">
          <span :if={detail.user && detail.user.username}>{detail.user.username}</span>
          <.link
            navigate={~p"/admin/generic/#{@user_id}?resource=users"}
            class="link link-hover"
          >
            user #{@user_id}
          </.link>
          <.stripe_customer_link
            :if={detail.client}
            id="stripe-customer"
            customer_id={detail.client.stripe_customer_id}
            show_id
          />
        </div>

        <%!-- ── Brief ─────────────────────────────────────────────────── --%>
        <div
          id="usage-brief"
          class={[
            "rounded-box border p-4 mb-6",
            if(at_risk?(detail.client),
              do: "border-warning bg-warning/5",
              else: "border-base-300 bg-base-100"
            )
          ]}
        >
          <h2 class="text-sm font-semibold uppercase text-base-content/60 mb-2">
            Before you contact them
          </h2>
          <.async_result :let={usage} assign={@usage}>
            <:loading>
              <div class="flex items-center gap-2 text-sm text-base-content/60">
                <span class="loading loading-spinner loading-xs"></span> Reading their usage...
              </div>
            </:loading>
            <:failed>
              <p class="text-sm text-error">Their usage could not be read.</p>
            </:failed>
            <ul class="list-disc list-inside space-y-1 text-sm">
              <li
                :for={
                  line <-
                    ClientUsage.summary(detail.client || %{}, usage.api, usage.web, usage.creations)
                }
                class="brief-line"
              >
                {line}
              </li>
            </ul>
            <p
              :if={Enum.any?([usage.api, usage.web, usage.creations], &(&1 == :error))}
              id="usage-partial"
              class="text-xs text-warning mt-2"
            >
              Part of the usage could not be read; the summary may miss something.
            </p>
          </.async_result>
        </div>

        <div
          :if={is_nil(detail.client)}
          id="not-a-client"
          role="alert"
          class="alert alert-info mb-6"
        >
          <.icon name="hero-information-circle" class="w-5 h-5" />
          <span>
            Not a business client today<.note_mark key={:business_client} notes={@notes} />.
            The invoices and the log below still apply.
          </span>
        </div>

        <%!-- ── Summary ──────────────────────────────────────────────── --%>
        <div :if={detail.client} id="client-summary" class="mb-8">
          <div class="grid grid-cols-2 md:grid-cols-4 gap-4 mb-4">
            <div class="card bg-base-100 border border-base-300 p-4">
              <div class="text-xs uppercase text-base-content/60">MRR</div>
              <div class="text-2xl font-bold tabular-nums">{money(detail.client.mrr)}</div>
              <div class="text-xs text-base-content/60">
                {detail.client.plan_name} · {detail.client.interval}
              </div>
            </div>
            <div class="card bg-base-100 border border-base-300 p-4">
              <div class="text-xs uppercase text-base-content/60">
                ACV<.note_mark key={:acv} notes={@notes} />
              </div>
              <div class="text-2xl font-bold tabular-nums">{money(detail.client.acv)}</div>
            </div>
            <div class="card bg-base-100 border border-base-300 p-4">
              <div class="text-xs uppercase text-base-content/60">
                TCV<.note_mark key={:tcv} notes={@notes} />
              </div>
              <div class="text-2xl font-bold tabular-nums">{money(detail.client.tcv)}</div>
              <div class="text-xs text-base-content/60">
                since {format_date(detail.client.start_date)}
              </div>
              <div id="client-tenure" class="text-xs text-base-content/60">
                client for {tenure(detail.client.start_date, @today, :long)}
              </div>
            </div>
            <div class="card bg-base-100 border border-base-300 p-4">
              <div class="text-xs uppercase text-base-content/60">Renewal</div>
              <div
                id="renewal-date"
                class={[
                  "text-2xl font-bold tabular-nums",
                  renewal_highlight?(detail.client, @settings.renewal_intervals, @today) &&
                    "text-warning"
                ]}
              >
                {format_date(detail.client.renewal_date)}
              </div>
              <div
                :if={renewal_highlight?(detail.client, @settings.renewal_intervals, @today)}
                id="renewal-soon"
                class="text-xs text-warning"
              >
                within 30 days
              </div>
            </div>
          </div>

          <div class="rounded-box border border-base-300 overflow-x-auto">
            <table class="table table-sm">
              <tbody>
                <tr>
                  <th class="w-56 text-base-content/60 font-normal">Plan</th>
                  <td>
                    {detail.client.plan_name}
                    <span class="text-base-content/60">
                      (product {detail.client.product_id}, {detail.client.interval})
                    </span>
                  </td>
                </tr>
                <tr>
                  <th class="text-base-content/60 font-normal">
                    Business because<.note_mark key={:business_client} notes={@notes} />
                  </th>
                  <td>
                    <.reason_badge
                      reason={detail.client.business_reason}
                      override={detail.client.override}
                    />
                  </td>
                </tr>
                <tr>
                  <th class="text-base-content/60 font-normal">Subscription status</th>
                  <td>
                    {detail.client.subscription_status || "-"}
                    <span
                      :if={detail.client.failed_payment?}
                      id="failed-payment"
                      class="badge badge-sm badge-error ml-2"
                      title="The business subscription is past due or unpaid: a charge failed"
                    >
                      <.icon name="hero-exclamation-triangle" class="w-3 h-3" /> payment failed
                    </span>
                    <span
                      :if={detail.client.unpaid_invoice?}
                      id="unpaid-invoice"
                      class="badge badge-sm badge-warning badge-soft ml-2"
                      title="A business invoice has been open for more than 7 days - e.g. a wire or crypto payment not received yet"
                    >
                      <.icon name="hero-clock" class="w-3 h-3" /> unpaid invoice
                    </span>
                  </td>
                </tr>
                <tr>
                  <th class="text-base-content/60 font-normal">Paid by</th>
                  <td>
                    <div class="flex flex-wrap gap-1">
                      <span
                        :for={{source, amount} <- paid_by_mix(detail.client.paid_by)}
                        class={["badge badge-sm", paid_by_badge_class(source)]}
                      >
                        {paid_by_label(source)}: {money(amount)}
                      </span>
                      <span
                        :if={paid_by_mix(detail.client.paid_by) == []}
                        class="text-base-content/50"
                      >
                        -
                      </span>
                    </div>
                  </td>
                </tr>
                <tr>
                  <th class="text-base-content/60 font-normal">
                    API calls<.note_mark key={:usage} notes={@notes} />
                  </th>
                  <td class="tabular-nums">
                    {format_number(detail.client.api_calls)}
                    <span class="text-base-content/60">
                      (previous window: {format_number(detail.client.api_calls_prev)})
                    </span>
                  </td>
                </tr>
                <tr>
                  <th class="text-base-content/60 font-normal">
                    Last active<.note_mark key={:usage} notes={@notes} />
                  </th>
                  <td id="last-active">
                    {format_datetime(detail.client.last_active_at)}
                    <span :if={activity_source(detail.client)} class="badge badge-xs badge-ghost ml-1">
                      {activity_source(detail.client)}
                    </span>
                    <span class="text-base-content/60 ml-2">
                      (web: {format_datetime(detail.client.last_web_active_at)}, API: {format_datetime(
                        detail.client.last_api_call_at
                      )})
                    </span>
                  </td>
                </tr>
                <tr>
                  <th class="text-base-content/60 font-normal">
                    Active days<.note_mark key={:risk} notes={@notes} />
                  </th>
                  <td id="active-days" class="tabular-nums">
                    {format_number(detail.client.active_days)}
                    <span class="text-base-content/60">
                      (previous window: {format_number(detail.client.active_days_prev)})
                    </span>
                  </td>
                </tr>
                <tr>
                  <th class="text-base-content/60 font-normal align-top">
                    Risk level<.note_mark key={:risk} notes={@notes} />
                  </th>
                  <td>
                    <.risk_level
                      id="risk-level"
                      level={detail.client.risk_level}
                      reasons={detail.client.risk_reasons}
                    />
                  </td>
                </tr>
                <tr>
                  <th class="text-base-content/60 font-normal">
                    Manual status<.note_mark key={:at_risk} notes={@notes} />
                  </th>
                  <td>
                    <.status_badge status={detail.client.manual_status} />
                    <span class="text-base-content/60 ml-2">
                      {detail.client.open_entries_count} open entr(ies)
                    </span>
                  </td>
                </tr>
                <tr>
                  <th class="text-base-content/60 font-normal">
                    Retention action<.note_mark key={:retention} notes={@notes} />
                  </th>
                  <td>{if detail.client.retention_action?, do: "Yes", else: "No"}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <%!-- ── Plan limit ───────────────────────────────────────────── --%>
        <div
          :if={detail.client && detail.client.plan_limit}
          id="plan-limit"
          class="card bg-base-100 border border-base-300 p-4 mb-8"
        >
          <div class="flex flex-wrap items-baseline gap-3 mb-1">
            <h2 class="text-lg font-semibold">
              Monthly API limit<.note_mark key={:plan_limit} notes={@notes} />
            </h2>
            <span class="text-sm text-base-content/60">
              {limit_label(detail.client.plan_limit.limit)}
            </span>
            <span
              :if={detail.client.plan_limit.upsell?}
              id="upsell-badge"
              class="badge badge-sm badge-success"
              title={detail.client.plan_limit.upsell_reason}
            >
              <.icon name="hero-arrow-trending-up" class="w-3 h-3" /> upsell candidate
            </span>
          </div>
          <p
            :if={detail.client.plan_limit.upsell_reason}
            class="text-sm text-base-content/70 mb-3"
          >
            {detail.client.plan_limit.upsell_reason}.
          </p>
          <div class="overflow-x-auto">
            <table id="plan-limit-months" class="table table-xs">
              <thead>
                <tr>
                  <th :for={m <- detail.client.plan_limit.months}>{month_label(m.month)}</th>
                  <th>This month (pace)</th>
                </tr>
              </thead>
              <tbody>
                <tr class="tabular-nums">
                  <td :for={m <- detail.client.plan_limit.months}>
                    <div>{format_number(m.calls)}</div>
                    <div class={[
                      "text-xs",
                      if((m.share || 0) >= 0.8,
                        do: "text-success font-semibold",
                        else: "text-base-content/60"
                      )
                    ]}>
                      {percent(m.share)}
                    </div>
                  </td>
                  <td>
                    <div>{format_number(detail.client.plan_limit.pace.calls)}</div>
                    <div class="text-xs text-base-content/60">
                      {percent(detail.client.plan_limit.pace.share)}{if detail.client.plan_limit.pace.partial?,
                        do: " (early in the month)"}
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <%!-- ── Usage ────────────────────────────────────────────────── --%>
        <.async_result :let={usage} assign={@usage}>
          <:loading></:loading>
          <:failed></:failed>
          <div id="api-usage" class="mb-8">
            <h2 class="text-xl font-semibold mb-1">API usage</h2>
            <p class="text-sm text-base-content/60 mb-3">
              API key calls in the last {ClientUsage.window_days()} whole days against the {ClientUsage.window_days()} days before.
            </p>
            <%= case usage.api do %>
              <% :error -> %>
                <p class="text-sm text-error">The API usage could not be read.</p>
              <% {:ok, %{calls: %{current: 0, previous: 0}}} -> %>
                <p id="no-api-calls" class="text-sm text-base-content/60">
                  No API key calls in the last {2 * ClientUsage.window_days()} days.
                </p>
              <% {:ok, api} -> %>
                <div class="flex flex-wrap gap-6 text-sm mb-4">
                  <div>
                    <span class="text-base-content/60">Calls:</span>
                    <span class="font-semibold tabular-nums">{format_number(api.calls.current)}</span>
                    <span class="text-base-content/60">
                      (was {format_number(api.calls.previous)}, <span class={
                        change_class(api.calls.current, api.calls.previous)
                      }>
                        {change_label(api.calls.current, api.calls.previous)}
                      </span>)
                    </span>
                  </div>
                  <div>
                    <span class="text-base-content/60">Failed calls:</span>
                    <span class="font-semibold tabular-nums">{format_number(api.errors)}</span>
                  </div>
                  <div id="api-connections">
                    <span class="text-base-content/60">Connects with:</span>
                    <span
                      :for={c <- Enum.take(api.connections, 3)}
                      class="badge badge-sm badge-ghost ml-1"
                    >
                      {c.label} {percent(c.share)}
                    </span>
                  </div>
                </div>

                <div
                  :if={stopped_queries(api) != []}
                  id="stopped-queries"
                  class="alert alert-warning mb-4 text-sm"
                >
                  <.icon name="hero-exclamation-triangle" class="w-5 h-5" />
                  <div>
                    <div class="font-semibold">Stopped or almost stopped using</div>
                    <span :for={q <- stopped_queries(api)} class="mr-3 whitespace-nowrap">
                      {ClientUsage.query_label(q.name)}
                      <span class="tabular-nums">
                        ({format_number(q.previous)} → {format_number(q.current)})
                      </span>
                    </span>
                  </div>
                </div>

                <div class="grid grid-cols-1 lg:grid-cols-3 gap-4">
                  <div class="lg:col-span-2 rounded-box border border-base-300 overflow-x-auto">
                    <table id="api-queries" class="table table-xs">
                      <thead>
                        <tr>
                          <th>Metric or query</th>
                          <th class="text-right">Last {ClientUsage.window_days()} days</th>
                          <th class="text-right">Before</th>
                          <th class="text-right">Change</th>
                          <th class="text-right">Failed</th>
                        </tr>
                      </thead>
                      <tbody>
                        <tr :for={q <- top(api.queries, 15)} class="tabular-nums">
                          <td class="font-mono text-xs break-all">
                            {ClientUsage.query_label(q.name)}
                          </td>
                          <td class="text-right">{format_number(q.current)}</td>
                          <td class="text-right text-base-content/60">{format_number(q.previous)}</td>
                          <td class={["text-right", change_class(q.current, q.previous)]}>
                            {change_label(q.current, q.previous)}
                          </td>
                          <td class={["text-right", q.errors > 0 && "text-error"]}>
                            {format_number(q.errors)}
                          </td>
                        </tr>
                      </tbody>
                    </table>
                  </div>
                  <div class="rounded-box border border-base-300 overflow-x-auto">
                    <table id="api-assets" class="table table-xs">
                      <thead>
                        <tr>
                          <th>Asset</th>
                          <th class="text-right">Last {ClientUsage.window_days()} days</th>
                          <th class="text-right">Change</th>
                        </tr>
                      </thead>
                      <tbody>
                        <tr :for={a <- top(api.assets, 15)} class="tabular-nums">
                          <td class="break-all">{a.slug}</td>
                          <td class="text-right">{format_number(a.current)}</td>
                          <td class={["text-right", change_class(a.current, a.previous)]}>
                            {change_label(a.current, a.previous)}
                          </td>
                        </tr>
                        <tr :if={top(api.assets, 15) == []}>
                          <td colspan="3" class="text-base-content/60">No asset-specific calls.</td>
                        </tr>
                      </tbody>
                    </table>
                  </div>
                </div>
            <% end %>
          </div>

          <div id="sanbase-usage" class="mb-8">
            <h2 class="text-xl font-semibold mb-1">Sanbase usage</h2>
            <p class="text-sm text-base-content/60 mb-3">
              Page views per area of the app, SQL queries run, and what they have built.
            </p>
            <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
              <div class="rounded-box border border-base-300 overflow-x-auto">
                <%= case usage.web do %>
                  <% :error -> %>
                    <p class="p-4 text-sm text-error">The web app usage could not be read.</p>
                  <% {:ok, web} -> %>
                    <table id="web-areas" class="table table-xs">
                      <thead>
                        <tr>
                          <th>Area</th>
                          <th class="text-right">Views, last {ClientUsage.window_days()} days</th>
                          <th class="text-right">Before</th>
                        </tr>
                      </thead>
                      <tbody>
                        <tr :for={a <- web.areas} class="tabular-nums">
                          <td>{a.area}</td>
                          <td class="text-right">{format_number(a.current)}</td>
                          <td class="text-right text-base-content/60">{format_number(a.previous)}</td>
                        </tr>
                        <tr id="sql-runs" class="tabular-nums">
                          <td>SQL queries run</td>
                          <td class="text-right">{format_number(web.sql_runs.current)}</td>
                          <td class="text-right text-base-content/60">
                            {format_number(web.sql_runs.previous)}
                          </td>
                        </tr>
                      </tbody>
                    </table>
                    <p :if={web.areas == []} class="px-4 pb-3 text-sm text-base-content/60">
                      No page views in the last {2 * ClientUsage.window_days()} days.
                    </p>
                <% end %>
              </div>
              <div class="rounded-box border border-base-300 overflow-x-auto">
                <%= case usage.creations do %>
                  <% :error -> %>
                    <p class="p-4 text-sm text-error">What they built could not be read.</p>
                  <% {:ok, creations} -> %>
                    <table id="creations" class="table table-xs">
                      <thead>
                        <tr>
                          <th>Built</th>
                          <th class="text-right">Total</th>
                          <th class="text-right">Changed, last {ClientUsage.window_days()} days</th>
                          <th>Last changed</th>
                        </tr>
                      </thead>
                      <tbody>
                        <tr
                          :for={c <- ClientUsage.sort_creations(creations)}
                          id={"creation-#{c.kind}"}
                          class="tabular-nums"
                        >
                          <td>
                            {c.label}
                            <div :if={c.kind == :alerts} class="text-xs text-base-content/60">
                              {c.active || 0} on, last fired {format_datetime(c.last_fired_at)}
                            </div>
                          </td>
                          <td class="text-right">{format_number(c.total)}</td>
                          <td class="text-right">{format_number(c.changed_recently)}</td>
                          <td class="whitespace-nowrap">{format_datetime(c.last_changed_at)}</td>
                        </tr>
                      </tbody>
                    </table>
                <% end %>
              </div>
            </div>
          </div>
        </.async_result>

        <%!-- ── Override ─────────────────────────────────────────────── --%>
        <div
          :if={override_applies?(detail.client, @override)}
          id="override-panel"
          class="card bg-base-100 border border-base-300 p-4 mb-8"
        >
          <h2 class="text-lg font-semibold mb-1">Business override</h2>
          <p class="text-sm text-base-content/60 mb-3">
            On a plan that needs a business email, the email domain decides whether this
            user counts. Override it when the domain rule is wrong.
          </p>

          <div id="override-state" class="text-sm mb-3">
            <%= if @override do %>
              Currently overridden as
              <span class={[
                "badge badge-sm",
                if(@override.business, do: "badge-success", else: "badge-ghost")
              ]}>
                {if @override.business, do: "business", else: "not business"}
              </span>
              by {user_label(@override.set_by)} on {format_datetime(@override.updated_at)}.
              <span :if={@override.note} class="text-base-content/70">
                Note: {@override.note}
              </span>
            <% else %>
              <span class="text-base-content/60">No override - the email domain rule applies.</span>
            <% end %>
          </div>

          <.form
            :if={can_edit?(assigns)}
            for={@override_form}
            id="override-form"
            phx-submit="set_override"
            class="flex flex-wrap items-end gap-3"
          >
            <.input
              field={@override_form[:business]}
              type="select"
              label="Counts as business"
              options={[{"Yes", "true"}, {"No", "false"}]}
              outer_div_class="w-40"
            />
            <.input
              field={@override_form[:note]}
              type="text"
              label="Why"
              placeholder="e.g. company uses gmail for billing"
              outer_div_class="w-96"
            />
            <div class="flex items-center gap-2 mb-2">
              <button id="save-override" type="submit" class="btn btn-sm btn-primary">
                Save override
              </button>
              <button
                :if={@override}
                id="clear-override"
                type="button"
                phx-click="clear_override"
                data-confirm="Clear the override and let the email domain decide?"
                class="btn btn-sm btn-soft btn-error"
              >
                Clear override
              </button>
            </div>
          </.form>
        </div>

        <%!-- ── Invoices ─────────────────────────────────────────────── --%>
        <h2 class="text-xl font-semibold mb-2">Invoices</h2>
        <p class="text-sm text-base-content/60 mb-2">
          From the Stripe invoice mirror, newest first, with the plan lines each one paid for.
        </p>
        <div class="rounded-box border border-base-300 overflow-x-auto mb-8">
          <table id="invoices-table" class="table table-sm">
            <thead>
              <tr>
                <th>Invoice</th>
                <th>Date</th>
                <th>Status</th>
                <th class="text-right">Total excl. tax</th>
                <th class="text-right">Paid by card</th>
                <th class="text-right">Credit applied</th>
                <th>Source</th>
              </tr>
            </thead>
            <tbody :if={detail.invoices == []}>
              <tr>
                <td colspan="7" class="text-center text-base-content/60 py-6">
                  No invoices in the mirror for this user.
                </td>
              </tr>
            </tbody>
            <tbody
              :for={invoice <- detail.invoices}
              id={"invoice-#{invoice.stripe_invoice_id}"}
              class="border-b border-base-300"
            >
              <tr class="hover:bg-base-200 transition-colors">
                <td>
                  <.link
                    href={CreditPayments.stripe_invoice_url(invoice.stripe_invoice_id)}
                    target="_blank"
                    class="link link-primary font-mono text-xs"
                    title="Open the invoice in Stripe"
                  >
                    {invoice.invoice_number || invoice.stripe_invoice_id}
                  </.link>
                </td>
                <td class="whitespace-nowrap">{format_date(invoice.invoiced_at)}</td>
                <td>
                  <span class={["badge badge-xs", invoice_status_class(invoice.status)]}>
                    {invoice.status}
                  </span>
                </td>
                <td class="text-right tabular-nums font-medium">
                  {money_exact(invoice.total_excluding_tax)}
                </td>
                <td class="text-right tabular-nums">{money_exact(invoice.amount_paid)}</td>
                <td class="text-right tabular-nums">{money_exact(invoice.credit_applied)}</td>
                <td>
                  <span class={["badge badge-xs", source_class(invoice.source)]}>
                    {source_label(invoice.source)}
                  </span>
                  <span :if={invoice.paid_out_of_band} class="badge badge-xs badge-info">
                    out of band
                  </span>
                </td>
              </tr>
              <tr :for={line <- invoice.lines} class="text-xs text-base-content/70">
                <td></td>
                <td colspan="2" class="whitespace-nowrap">
                  {format_date(line.period_start)} - {format_date(line.period_end)}
                </td>
                <td class="text-right tabular-nums">{money_exact(line.net_amount)}</td>
                <td colspan="3">
                  {line.plan_name || "-"}
                  <span :if={line.discount > 0} class="badge badge-xs badge-outline ml-1">
                    {money_exact(line.discount)} discount
                  </span>
                  <span :if={line.proration} class="badge badge-xs badge-outline ml-1">
                    proration
                  </span>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </.async_result>

      <%!-- ── Log ──────────────────────────────────────────────────── --%>
      <h2 class="text-xl font-semibold mb-2">Log</h2>
      <p class="text-sm text-base-content/60 mb-2">
        What people noticed or did about this client. The most severe open entry sets the
        manual status until it is resolved. {@open_entries_count} of {@entries_count} open.
      </p>

      <div
        :if={can_edit?(assigns)}
        id="add-entry-panel"
        class="card bg-base-100 border border-base-300 p-4 mb-4 scroll-mt-20 target:border-primary transition-colors"
      >
        <.form
          for={@entry_form}
          id="entry-form"
          phx-change="validate_entry"
          phx-submit="add_entry"
          class="grid grid-cols-1 md:grid-cols-[14rem_12rem_1fr_auto] gap-x-3 items-end"
        >
          <.input
            field={@entry_form[:type]}
            type="select"
            label="Type"
            prompt="Choose a type"
            options={@settings.issue_types}
          />
          <.input
            field={@entry_form[:severity]}
            type="select"
            label="Severity"
            options={Enum.map(LogEntry.severities(), &{severity_label(&1), &1})}
            disabled={severity_disabled?(@entry_form, @settings)}
          />
          <.input
            field={@entry_form[:note]}
            type="textarea"
            label="Note"
            rows="2"
            placeholder="What happened, who said what"
          />
          <button id="add-entry" type="submit" class="btn btn-sm btn-primary mb-3">
            Add entry
          </button>
        </.form>
        <p
          :if={severity_disabled?(@entry_form, @settings)}
          id="severity-disabled-hint"
          class="text-xs text-base-content/60"
        >
          This type carries no severity, so it does not change the manual status.
        </p>
      </div>

      <div class="rounded-box border border-base-300 overflow-x-auto mb-8">
        <table class="table table-sm">
          <thead>
            <tr>
              <th>Added</th>
              <th>Type</th>
              <th>Severity</th>
              <th>Note</th>
              <th>By</th>
              <th>Resolved</th>
            </tr>
          </thead>
          <tbody id="log-entries" phx-update="stream">
            <tr id="log-entries-empty" class="hidden only:table-row">
              <td colspan="6" class="text-center text-base-content/60 py-6">
                Nothing logged for this client yet.
              </td>
            </tr>
            <tr
              :for={{dom_id, entry} <- @streams.entries}
              id={dom_id}
              class={[
                "hover:bg-base-200 transition-colors",
                entry.resolved_at && "text-base-content/50"
              ]}
            >
              <td class="whitespace-nowrap">{format_datetime(entry.inserted_at)}</td>
              <td class="whitespace-nowrap font-medium">{entry.type}</td>
              <td>
                <span class={["badge badge-xs", severity_badge_class(entry.severity)]}>
                  {severity_label(entry.severity)}
                </span>
              </td>
              <td class="max-w-md whitespace-pre-line break-words">{entry.note}</td>
              <td class="whitespace-nowrap">{user_label(entry.author)}</td>
              <td class="whitespace-nowrap">
                <%= if entry.resolved_at do %>
                  <span class="text-xs">
                    {format_datetime(entry.resolved_at)} by {user_label(entry.resolved_by)}
                  </span>
                <% else %>
                  <button
                    :if={can_edit?(assigns)}
                    id={"resolve-entry-#{entry.id}"}
                    type="button"
                    phx-click="resolve_entry"
                    phx-value-id={entry.id}
                    class="btn btn-xs btn-soft btn-success"
                  >
                    <.icon name="hero-check" class="w-3 h-3" /> Resolve
                  </button>
                  <span :if={!can_edit?(assigns)} class="badge badge-xs badge-outline">open</span>
                <% end %>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <.formula_notes notes={@notes} open={@notes_open} />
    </div>
    """
  end
end
