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
      renewal_soon?: 2,
      severity_label: 1,
      status_badge: 1,
      reason_badge: 1,
      note_mark: 1,
      formula_notes: 1,
      paid_by_mix: 1,
      paid_by_label: 1,
      paid_by_badge_class: 1
    ]

  alias Sanbase.Admin.Permissions
  alias Sanbase.Billing.BusinessClients
  alias Sanbase.Billing.BusinessClients.{LogEntry, Override}
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
          |> assign_entry_form(BusinessClients.change_entry(%{}))
          |> assign(:override_form, to_form(%{"business" => "true", "note" => ""}, as: :override))
          |> load_entries()
          |> load_override()
          |> load_detail()

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
          <.link
            :if={detail.client && detail.client.stripe_customer_id}
            href={CreditPayments.stripe_customer_url(detail.client.stripe_customer_id)}
            target="_blank"
            class="link link-hover font-mono"
          >
            {detail.client.stripe_customer_id}
          </.link>
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
            </div>
            <div class="card bg-base-100 border border-base-300 p-4">
              <div class="text-xs uppercase text-base-content/60">Renewal</div>
              <div class={[
                "text-2xl font-bold tabular-nums",
                renewal_soon?(detail.client.renewal_date, @today) && "text-warning"
              ]}>
                {format_date(detail.client.renewal_date)}
              </div>
              <div
                :if={renewal_soon?(detail.client.renewal_date, @today)}
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
                    >
                      <.icon name="hero-exclamation-triangle" class="w-3 h-3" /> payment failed
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
                  <th class="text-base-content/60 font-normal">Last active</th>
                  <td>{format_datetime(detail.client.last_active_at)}</td>
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
                <td class="text-right tabular-nums">{money_exact(line.amount_excluding_tax)}</td>
                <td colspan="3">
                  {line.plan_name || "-"}
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
        class="card bg-base-100 border border-base-300 p-4 mb-4"
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

      <.formula_notes notes={@notes} />
    </div>
    """
  end
end
