defmodule SanbaseWeb.Admin.BusinessClientsLive do
  @moduledoc """
  Business clients: who they are, what they pay, churn and renewal, and the manual
  health log. The numbers come from `Sanbase.Billing.BusinessClients`, which reads the
  Stripe invoice mirror; the mirror is refreshed by
  `Sanbase.Billing.InvoiceMirror.SyncJob`, which this page can start.

  Viewing needs any Admin Panel role, re-importing and the quick log link need Editor,
  and changing the settings needs Owner: everyone sees the settings read-only, an
  owner unlocks them with Edit. The formatting helpers and badges are public so the detail
  page (`SanbaseWeb.Admin.BusinessClientLive`) renders the same way.
  """
  use SanbaseWeb, :live_view

  import SanbaseWeb.AdminLiveHelpers, only: [parse_int: 2]

  alias Phoenix.LiveView.AsyncResult
  alias Sanbase.Admin.Permissions
  alias Sanbase.Billing.BusinessClients
  alias Sanbase.Billing.BusinessClients.Settings
  alias Sanbase.Billing.CreditPayments
  alias Sanbase.Billing.InvoiceMirror
  alias Sanbase.Billing.InvoiceMirror.SyncJob

  @months 12
  @max_resync_years 3
  @renewal_soon_days 30
  @sort_keys %{"mrr" => :mrr, "acv" => :acv, "renewal_date" => :renewal_date}
  @statuses [:healthy, :at_risk, :high_risk]
  @reasons [:plan, :business_email, :override]
  @segments [:plan, :business_email]
  @monthly_segments %{"total" => :total, "plan" => :plan, "business_email" => :business_email}
  @paid_by_keys [:card, :wire, :crypto, :san_burn, :stripe_credit, :other, :unknown, :out_of_band]
  @note_keys [
    :business_client,
    :acv,
    :tcv,
    :client_churn,
    :revenue_churn,
    :client_renewal,
    :revenue_renewal,
    :at_risk,
    :retention,
    :churned,
    :usage
  ]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: SyncJob.subscribe()

    today = Date.utc_today()
    settings = BusinessClients.settings()

    socket =
      socket
      |> assign(:page_title, "Business Clients")
      |> assign(:today, today)
      |> assign(:settings, settings)
      |> assign(:notes, BusinessClients.formula_notes(settings))
      |> assign(:filters, default_filters())
      |> assign(:sort_by, :mrr)
      |> assign(:sort_dir, :desc)
      |> assign(:sync_job, SyncJob.get_state())
      |> assign(:last_synced_at, InvoiceMirror.last_synced_at())
      |> assign(:resync_from, today |> Date.shift(month: -@months) |> Date.beginning_of_month())
      |> assign(:resync_to, today)
      |> assign_settings_form(Settings.validate(%{}))
      |> assign(:settings_last_change, settings_last_change())
      # Both sections start collapsed and the settings read-only.
      |> assign(:settings_open, false)
      |> assign(:settings_editing, false)
      |> assign(:notes_open, false)
      # Which numbers the monthly table shows: the totals or one segment's.
      |> assign(:monthly_segment, :total)
      # The full client list, kept for in-memory filtering and sorting; the table renders
      # the `:clients` stream.
      |> assign(:clients, [])
      |> assign(:client_total, 0)
      |> assign(:visible_count, 0)
      |> assign(:plan_options, plan_options([]))
      |> assign(:report, AsyncResult.loading())
      |> stream_configure(:clients, dom_id: &"client-#{&1.user_id}")
      |> stream(:clients, [])
      |> assign(:churned_count, 0)
      |> assign(:churned_lost_mrr, 0)
      |> stream_configure(:churned, dom_id: &"churned-#{&1.user_id}")
      |> stream(:churned, [])
      |> load_report()

    {:ok, socket}
  end

  # ─── Events ──────────────────────────────────────────────────────────────

  @impl true
  def handle_event("filter", params, socket) do
    filters = %{
      plan: params["plan"] || "all",
      status: parse_choice(params["status"], @statuses),
      reason: parse_choice(params["reason"], @reasons),
      renewal_within: parse_int(params["renewal_within"], nil),
      query: String.trim(params["query"] || "")
    }

    {:noreply, socket |> assign(:filters, filters) |> stream_clients()}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply, socket |> assign(:filters, default_filters()) |> stream_clients()}
  end

  def handle_event("sort", %{"by" => by}, socket) do
    case Map.fetch(@sort_keys, by) do
      {:ok, key} ->
        dir =
          cond do
            key != socket.assigns.sort_by -> default_dir(key)
            socket.assigns.sort_dir == :desc -> :asc
            true -> :desc
          end

        {:noreply, socket |> assign(:sort_by, key) |> assign(:sort_dir, dir) |> stream_clients()}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("refresh", _params, socket) do
    {:noreply, load_report(socket)}
  end

  def handle_event("resync", params, socket) do
    if can_edit?(socket.assigns) do
      from = parse_date(params["from"], socket.assigns.resync_from)
      to = parse_date(params["to"], socket.assigns.resync_to)
      socket = socket |> assign(:resync_from, from) |> assign(:resync_to, to)

      with :ok <- validate_resync_range(from, to),
           :ok <- start_sync(from, to, socket.assigns.current_user.id) do
        {:noreply, assign(socket, :sync_job, SyncJob.get_state())}
      else
        {:error, :already_running} ->
          {:noreply, put_flash(socket, :error, "An import is already running")}

        {:error, message} when is_binary(message) ->
          {:noreply, put_flash(socket, :error, message)}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Could not start the import: #{inspect(reason)}")}
      end
    else
      {:noreply, put_flash(socket, :error, "Re-importing invoices needs the Editor role")}
    end
  end

  def handle_event("cancel_sync", _params, socket) do
    if can_edit?(socket.assigns), do: SyncJob.cancel()

    {:noreply, assign(socket, :sync_job, SyncJob.get_state())}
  end

  # A <summary> click toggles its <details> in the browser too; the assign follows it
  # so a re-render keeps the section the way the user left it.
  def handle_event("toggle_section", %{"section" => "settings"}, socket) do
    {:noreply, assign(socket, :settings_open, !socket.assigns.settings_open)}
  end

  def handle_event("toggle_section", %{"section" => "notes"}, socket) do
    {:noreply, assign(socket, :notes_open, !socket.assigns.notes_open)}
  end

  def handle_event("toggle_section", _params, socket), do: {:noreply, socket}

  def handle_event("monthly_segment", %{"segment" => segment}, socket) do
    {:noreply, assign(socket, :monthly_segment, Map.get(@monthly_segments, segment, :total))}
  end

  # An asterisk opens the formula notes; the link's own anchor jumps to the note.
  def handle_event("open_notes", _params, socket) do
    {:noreply, assign(socket, :notes_open, true)}
  end

  def handle_event("edit_settings", _params, socket) do
    if owner?(socket.assigns) do
      {:noreply,
       socket
       |> assign_settings_form(Settings.validate(%{}))
       |> assign(:settings_open, true)
       |> assign(:settings_editing, true)}
    else
      {:noreply, put_flash(socket, :error, "Changing the settings needs the Owner role")}
    end
  end

  def handle_event("cancel_settings", _params, socket) do
    {:noreply,
     socket
     |> assign_settings_form(Settings.validate(%{}))
     |> assign(:settings_editing, false)}
  end

  def handle_event("validate_settings", %{"settings" => params}, socket) do
    changeset =
      params
      |> normalize_settings_params()
      |> Settings.validate()
      |> Map.put(:action, :validate)

    {:noreply, assign_settings_form(socket, changeset)}
  end

  def handle_event("save_settings", %{"settings" => params}, socket) do
    if owner?(socket.assigns) do
      params = normalize_settings_params(params)

      case BusinessClients.update_settings(params, socket.assigns.current_user.id) do
        {:ok, settings} ->
          socket =
            socket
            |> assign(:settings, settings)
            |> assign(:notes, BusinessClients.formula_notes(settings))
            |> assign_settings_form(Settings.validate(%{}))
            |> assign(:settings_editing, false)
            |> assign(:settings_last_change, settings_last_change())
            |> put_flash(:info, "Settings saved - the numbers below are recomputed with them")
            |> load_report()

          {:noreply, socket}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply,
           socket
           |> assign_settings_form(Map.put(changeset, :action, :update))
           |> put_flash(:error, "The settings were not saved - check the highlighted fields")}
      end
    else
      {:noreply, put_flash(socket, :error, "Changing the settings needs the Owner role")}
    end
  end

  @impl true
  def handle_info({:sync_update, job_state}, socket) do
    # The mirror only changes when an import finishes, so that is the one moment the
    # numbers have to be read again. A finished job can be broadcast more than once;
    # only the change into `:done` reloads, so each job reloads at most once.
    just_finished? = job_state.status == :done and socket.assigns.sync_job.status != :done
    socket = assign(socket, :sync_job, job_state)

    socket =
      if just_finished? do
        socket
        |> assign(:last_synced_at, InvoiceMirror.last_synced_at())
        |> load_report()
      else
        socket
      end

    {:noreply, socket}
  end

  # ─── Loading ─────────────────────────────────────────────────────────────

  # One `BusinessClients.page/1` call loads the clients, the headline metrics and the
  # months together. While a reload runs the previous numbers stay on screen.
  defp load_report(socket) do
    as_of = socket.assigns.today
    coverage_from = as_of |> Date.shift(month: -@months) |> Date.beginning_of_month()

    socket
    |> assign(:report, AsyncResult.loading(socket.assigns.report))
    |> start_async(:report, fn ->
      [as_of: as_of, months: @months]
      |> BusinessClients.page()
      # Through yesterday: today is never fully imported, see `InvoiceMirror.coverage/2`.
      |> Map.put(:coverage, InvoiceMirror.coverage(coverage_from, Date.add(as_of, -1)))
    end)
  end

  @impl true
  def handle_async(:report, {:ok, report}, socket) do
    {clients, report} = Map.pop(report, :clients)
    {churned, report} = Map.pop(report, :churned, [])

    {:noreply,
     socket
     |> assign(:report, AsyncResult.ok(socket.assigns.report, report))
     |> assign(:clients, clients)
     |> assign(:client_total, length(clients))
     |> assign(:plan_options, plan_options(clients))
     |> stream_clients()
     |> assign(:churned_count, length(churned))
     |> assign(:churned_lost_mrr, churned |> Enum.map(& &1.lost_mrr) |> Enum.sum())
     |> stream(:churned, churned, reset: true)}
  end

  def handle_async(:report, {:exit, reason}, socket) do
    {:noreply,
     assign(socket, :report, AsyncResult.failed(socket.assigns.report, {:exit, reason}))}
  end

  defp stream_clients(socket) do
    %{clients: clients, filters: filters, sort_by: sort_by, sort_dir: sort_dir, today: today} =
      socket.assigns

    rows = visible_clients(clients, filters, sort_by, sort_dir, today)

    socket
    |> assign(:visible_count, length(rows))
    |> stream(:clients, rows, reset: true)
  end

  defp validate_resync_range(from, to) do
    cond do
      Date.compare(from, to) == :gt ->
        {:error, "The start date must not be after the end date"}

      Date.compare(Date.shift(from, year: @max_resync_years), to) == :lt ->
        {:error, "Re-import at most #{@max_resync_years} years at a time"}

      true ->
        :ok
    end
  end

  # The job GenServer may be down (e.g. not started on this node); report it rather
  # than crash the page.
  defp start_sync(from, to, user_id) do
    SyncJob.start_job(from, to, user_id)
  catch
    :exit, _reason -> {:error, "The import job is not running on this node"}
  end

  defp assign_settings_form(socket, changeset) do
    assign(socket, :settings_form, to_form(changeset, as: :settings))
  end

  defp settings_last_change do
    case Settings.last_change() do
      nil ->
        nil

      %{updated_at: at, updated_by_id: user_id} ->
        user = user_id && Sanbase.Repo.get(Sanbase.Accounts.User, user_id)
        %{updated_at: at, by: user && (user.email || user.username || "user ##{user.id}")}
    end
  end

  # `Settings.validate/1` splits the text lists itself, except the product ids, which
  # are integers and so arrive as one string from the text input.
  defp normalize_settings_params(params) do
    case params do
      %{"business_email_product_ids" => ids} when is_binary(ids) ->
        ids =
          ids
          |> String.split([",", "\n", " "])
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        Map.put(params, "business_email_product_ids", ids)

      _ ->
        params
    end
  end

  # ─── Permissions ─────────────────────────────────────────────────────────

  defp roles(assigns), do: assigns[:current_user_role_names] || []
  defp can_edit?(assigns), do: Permissions.can?(:edit, roles: roles(assigns))
  defp owner?(assigns), do: Permissions.owner?(roles: roles(assigns))

  # ─── Filtering and sorting ───────────────────────────────────────────────

  defp default_filters do
    %{plan: "all", status: :all, reason: :all, renewal_within: nil, query: ""}
  end

  defp default_dir(:renewal_date), do: :asc
  defp default_dir(_key), do: :desc

  defp parse_choice(value, allowed) do
    Enum.find(allowed, :all, &(Atom.to_string(&1) == value))
  end

  defp parse_date(value, fallback) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> fallback
    end
  end

  defp parse_date(_value, fallback), do: fallback

  defp visible_clients(clients, filters, sort_by, sort_dir, today) do
    clients
    |> Enum.filter(&matches?(&1, filters, today))
    |> sort_clients(sort_by, sort_dir)
  end

  defp matches?(client, filters, today) do
    (filters.plan == "all" or client.plan_name == filters.plan) and
      (filters.status == :all or client.manual_status == filters.status) and
      (filters.reason == :all or client.business_reason == filters.reason) and
      renews_within?(client, filters.renewal_within, today) and
      matches_query?(client, filters.query)
  end

  defp renews_within?(_client, nil, _today), do: true
  defp renews_within?(%{renewal_date: nil}, _days, _today), do: false

  defp renews_within?(%{renewal_date: date}, days, today) do
    diff = Date.diff(date, today)
    diff >= 0 and diff <= days
  end

  defp matches_query?(_client, ""), do: true

  defp matches_query?(client, query) do
    query = String.downcase(query)

    [client.email, client.username, client.stripe_customer_id, client.plan_name]
    |> Enum.any?(&(is_binary(&1) and String.contains?(String.downcase(&1), query)))
  end

  # Clients without a renewal date go last whatever the direction.
  defp sort_clients(clients, :renewal_date, dir) do
    {dated, undated} = Enum.split_with(clients, & &1.renewal_date)
    Enum.sort_by(dated, & &1.renewal_date, {dir, Date}) ++ undated
  end

  defp sort_clients(clients, key, dir) do
    Enum.sort_by(clients, &(Map.get(&1, key) || 0), dir)
  end

  defp plan_options(clients) do
    plans =
      clients
      |> Enum.map(& &1.plan_name)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.sort()

    [{"All plans", "all"} | Enum.map(plans, &{&1, &1})]
  end

  defp export_path(what), do: ~p"/admin/business_clients/export/#{what}"

  # ─── Shared formatting (also used by the detail page) ────────────────────

  @doc false
  def money(nil), do: "-"

  def money(cents) when is_integer(cents) do
    sign = if cents < 0, do: "-", else: ""
    "#{sign}$#{group_thousands(div(abs(cents) + 50, 100))}"
  end

  def money(%Decimal{} = cents), do: cents |> Decimal.round() |> Decimal.to_integer() |> money()
  def money(cents) when is_float(cents), do: cents |> round() |> money()

  @doc "Cents as dollars with the cents kept - for invoice amounts."
  def money_exact(nil), do: "-"

  def money_exact(cents) when is_integer(cents) do
    sign = if cents < 0, do: "-", else: ""
    cents = abs(cents)
    pennies = cents |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{sign}$#{group_thousands(div(cents, 100))}.#{pennies}"
  end

  def money_exact(%Decimal{} = cents),
    do: cents |> Decimal.round() |> Decimal.to_integer() |> money_exact()

  defp group_thousands(int) do
    int
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  @doc "A 0..1 rate as a percentage, `-` when it has no denominator."
  def rate(nil), do: "-"
  def rate(value) when is_number(value), do: percent(value * 100)
  def rate(%Decimal{} = value), do: value |> Decimal.to_float() |> rate()

  @doc "A 0..100 value as a percentage."
  def percent(nil), do: "-"
  def percent(value) when is_integer(value), do: "#{value}%"

  def percent(value) when is_float(value),
    do: "#{:erlang.float_to_binary(value, decimals: 1)}%"

  def percent(%Decimal{} = value), do: value |> Decimal.to_float() |> percent()

  def format_number(nil), do: "-"
  def format_number(n) when is_integer(n), do: group_thousands(n)
  def format_number(n), do: to_string(n)

  def format_date(nil), do: "-"
  def format_date(date), do: Calendar.strftime(date, "%Y-%m-%d")

  def format_datetime(nil), do: "-"
  def format_datetime(dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")

  def renewal_soon?(nil, _today), do: false

  def renewal_soon?(date, today) do
    diff = Date.diff(date, today)
    diff >= 0 and diff <= @renewal_soon_days
  end

  @doc ~s"""
  Whether a client's renewal date is highlighted: within #{@renewal_soon_days} days and
  on one of the renewal intervals (yearly by default). A monthly renewal is always that
  close, so highlighting it would flag every monthly client.
  """
  def renewal_highlight?(client, intervals, today) do
    client.interval in intervals and renewal_soon?(client.renewal_date, today)
  end

  @doc "The hint under the client table saying which renewals are highlighted."
  def renewal_hint([]), do: "No renewals are highlighted."

  def renewal_hint(intervals) do
    names = Enum.map_join(intervals, " and ", &interval_adjective/1)
    "#{names} renewals within #{@renewal_soon_days} days are highlighted."
  end

  defp interval_adjective("year"), do: "Yearly"
  defp interval_adjective("month"), do: "Monthly"
  defp interval_adjective(other), do: String.capitalize(to_string(other))

  @doc "Where the last activity came from: `\"API\"`, `\"web\"` or `nil` when never active."
  def activity_source(%{last_active_at: nil}), do: nil

  def activity_source(%{last_active_at: at, last_api_call_at: %DateTime{} = api}) do
    if DateTime.compare(api, at) == :eq, do: "API", else: "web"
  end

  def activity_source(_client), do: "web"

  def status_label(:healthy), do: "Healthy"
  def status_label(:at_risk), do: "At Risk"
  def status_label(:high_risk), do: "High Risk"
  def status_label(other), do: to_string(other)

  def reason_label(:plan), do: "Business plan"
  def reason_label(:business_email), do: "Business email"
  def reason_label(:override), do: "Override"
  def reason_label(:total), do: "Total"
  def reason_label(nil), do: "Not business"
  def reason_label(other), do: to_string(other)

  def severity_label("none"), do: "No severity"
  def severity_label("at_risk"), do: "At Risk"
  def severity_label("high_risk"), do: "High Risk"
  def severity_label(other), do: to_string(other)

  def paid_by_label(:card), do: "Card"
  def paid_by_label(:wire), do: "Wire"
  def paid_by_label(:crypto), do: "Crypto"
  def paid_by_label(:san_burn), do: "SAN burn"
  def paid_by_label(:stripe_credit), do: "Stripe credit"
  def paid_by_label(:other), do: "Other credit"
  def paid_by_label(:unknown), do: "Credit, no note"
  def paid_by_label(:out_of_band), do: "Out of band"
  def paid_by_label(other), do: to_string(other)

  def paid_by_badge_class(:card), do: "badge-primary"
  def paid_by_badge_class(:wire), do: "badge-info"
  def paid_by_badge_class(:crypto), do: "badge-success"
  def paid_by_badge_class(:san_burn), do: "badge-warning"
  def paid_by_badge_class(:stripe_credit), do: "badge-neutral"
  def paid_by_badge_class(_), do: "badge-ghost"

  @doc "The non-zero payment sources of a client, in a fixed order."
  def paid_by_mix(nil), do: []

  def paid_by_mix(paid_by) do
    @paid_by_keys
    |> Enum.map(&{&1, Map.get(paid_by, &1) || 0})
    |> Enum.reject(fn {_key, amount} -> amount == 0 end)
  end

  def note_keys, do: @note_keys
  def statuses, do: @statuses
  def reasons, do: @reasons
  def segments, do: @segments

  def note_label(:business_client), do: "Business client"
  def note_label(:acv), do: "ACV"
  def note_label(:tcv), do: "TCV"
  def note_label(:client_churn), do: "Client churn"
  def note_label(:revenue_churn), do: "Revenue churn"
  def note_label(:client_renewal), do: "Client renewal"
  def note_label(:revenue_renewal), do: "Revenue renewal"
  def note_label(:at_risk), do: "At risk"
  def note_label(:retention), do: "Retention actions"
  def note_label(:churned), do: "Recently churned"
  def note_label(:usage), do: "API usage"
  def note_label(other), do: to_string(other)

  # ─── Shared components ───────────────────────────────────────────────────

  attr(:status, :atom, required: true)

  def status_badge(assigns) do
    ~H"""
    <span class={[
      "badge badge-sm whitespace-nowrap",
      case @status do
        :high_risk -> "badge-error"
        :at_risk -> "badge-warning"
        _ -> "badge-success badge-soft"
      end
    ]}>
      {status_label(@status)}
    </span>
    """
  end

  attr(:reason, :atom, default: nil)
  attr(:override, :any, default: nil)

  def reason_badge(assigns) do
    ~H"""
    <span class="inline-flex items-center gap-1">
      <span class={[
        "badge badge-sm whitespace-nowrap",
        reason_badge_class(@reason)
      ]}>
        {reason_label(@reason)}
      </span>
      <span
        :if={is_boolean(@override) and @reason != :override}
        class="badge badge-xs badge-outline"
        title="An admin override decides whether this user counts as business"
      >
        override: {if @override, do: "yes", else: "no"}
      </span>
    </span>
    """
  end

  # Distinct hues per reason, readable on both themes: a translucent fill and border,
  # with a darker text on the light theme and a lighter one on the dark theme.
  defp reason_badge_class(:plan),
    do:
      "bg-indigo-500/15 border-indigo-500/30 text-indigo-700 [[data-theme=dark]_&]:text-indigo-200"

  defp reason_badge_class(:business_email),
    do: "bg-amber-500/15 border-amber-500/40 text-amber-800 [[data-theme=dark]_&]:text-amber-200"

  defp reason_badge_class(:override),
    do:
      "bg-purple-500/15 border-purple-500/30 text-purple-700 [[data-theme=dark]_&]:text-purple-200"

  defp reason_badge_class(_reason), do: "badge-ghost"

  # The dot of a segment, in the hue of its reason badge.
  defp segment_dot_class(:plan), do: "bg-indigo-500"
  defp segment_dot_class(:business_email), do: "bg-amber-500"
  defp segment_dot_class(_segment), do: "bg-base-content/40"

  # One segment's numbers; `nil` for a snapshot taken before the split.
  defp segment_metrics(metrics, segment) do
    case Map.get(metrics, :segments) do
      %{} = segments -> Map.get(segments, segment)
      _ -> nil
    end
  end

  # `{segment, text}` per segment for a headline card.
  defp breakdown(metrics, key) do
    for segment <- @segments, do: {segment, metric_text(segment_metrics(metrics, segment), key)}
  end

  defp metric_text(nil, _key), do: "-"
  defp metric_text(m, :client_count), do: format_number(m.client_count)
  defp metric_text(m, :mrr), do: money(m.mrr)
  defp metric_text(m, :at_risk_count), do: format_number(m.at_risk_count)
  defp metric_text(m, :retention_action_pct), do: percent(m.retention_action_pct)

  defp metric_text(%{client_churn: c}, :client_churn),
    do: "#{rate(c.rate)} · #{c.lost}/#{c.base}"

  defp metric_text(%{revenue_churn: r}, :revenue_churn),
    do: "#{rate(r.rate)} · #{money(r.lost_mrr)}/#{money(r.base_mrr)}"

  defp metric_text(%{client_renewal: c}, :client_renewal),
    do: "#{rate(c.rate)} · #{c.renewed}/#{c.due}"

  defp metric_text(%{revenue_renewal: r}, :revenue_renewal),
    do: "#{rate(r.rate)} · #{money(r.renewed_acv)}/#{money(r.due_acv)}"

  # `{month row, the numbers to show}`: the totals or the chosen segment's.
  defp monthly_rows(monthly, :total), do: Enum.map(monthly, &{&1, &1})
  defp monthly_rows(monthly, segment), do: Enum.map(monthly, &{&1, segment_metrics(&1, segment)})

  @doc "A small link to the customer in the Stripe dashboard; nothing without a customer id."
  attr(:customer_id, :string, default: nil)
  attr(:id, :string, required: true)
  attr(:show_id, :boolean, default: false, doc: "show the customer id next to the icon")

  def stripe_customer_link(assigns) do
    ~H"""
    <a
      :if={@customer_id}
      id={@id}
      href={CreditPayments.stripe_customer_url(@customer_id)}
      target="_blank"
      rel="noopener noreferrer"
      title="Open the customer in Stripe"
      class="inline-flex items-center gap-1 text-base-content/50 hover:text-primary transition-colors"
    >
      <span :if={@show_id} class="font-mono">{@customer_id}</span>
      <.icon name="hero-arrow-top-right-on-square" class="w-3.5 h-3.5" />
    </a>
    """
  end

  @doc ~s"""
  An asterisk that shows how a number is computed. Clicking it opens the collapsed
  formula notes (the page handles `open_notes`) and its anchor jumps to the note.
  """
  attr(:key, :atom, required: true)
  attr(:notes, :map, required: true)

  def note_mark(assigns) do
    ~H"""
    <a
      :if={Map.get(@notes, @key)}
      href={"#formula-#{@key}"}
      phx-click="open_notes"
      title={Map.get(@notes, @key)}
      class="text-primary hover:text-primary/70 font-semibold no-underline cursor-help transition-colors"
    >
      *
    </a>
    """
  end

  @doc ~s"""
  The formula notes, collapsed unless `open`. The summary sends `toggle_section` with
  `section: "notes"`, so the page keeps the state across re-renders.
  """
  attr(:notes, :map, required: true)
  attr(:open, :boolean, default: false)
  attr(:id, :string, default: "formula-notes")

  def formula_notes(assigns) do
    ~H"""
    <details id={@id} open={@open} class="group card bg-base-100 border border-base-300 p-4">
      <summary
        id={"#{@id}-toggle"}
        phx-click="toggle_section"
        phx-value-section="notes"
        class="flex items-center gap-2 cursor-pointer list-none select-none text-sm font-semibold uppercase tracking-wide text-base-content/60 hover:text-base-content transition-colors [&::-webkit-details-marker]:hidden"
      >
        <.icon
          name="hero-chevron-right"
          class="w-4 h-4 transition-transform duration-200 group-open:rotate-90"
        /> How the numbers are computed
      </summary>
      <dl class="grid grid-cols-1 md:grid-cols-2 gap-x-6 gap-y-2 text-sm mt-3">
        <div
          :for={key <- note_keys()}
          :if={Map.get(@notes, key)}
          id={"formula-#{key}"}
          class="scroll-mt-20 target:bg-warning/10 rounded px-1 transition-colors"
        >
          <dt class="font-medium"><span class="text-primary">*</span> {note_label(key)}</dt>
          <dd class="text-base-content/70">{Map.get(@notes, key)}</dd>
        </div>
      </dl>
    </details>
    """
  end

  # ─── Page components ─────────────────────────────────────────────────────

  attr(:id, :string, required: true)
  attr(:label, :string, required: true)
  attr(:value, :string, required: true)
  attr(:sub, :string, default: nil)
  attr(:note, :atom, required: true)
  attr(:notes, :map, required: true)
  attr(:accent, :string, default: nil)
  attr(:breakdown, :list, default: [], doc: "`{segment, text}` lines under the value")

  defp metric_card(assigns) do
    ~H"""
    <div
      id={@id}
      class="card bg-base-100 border border-base-300 p-4 hover:border-base-content/30 transition-colors"
    >
      <div class="text-xs uppercase text-base-content/60">
        {@label}<.note_mark key={@note} notes={@notes} />
      </div>
      <div class={["text-2xl font-bold tabular-nums", @accent]}>{@value}</div>
      <div :if={@sub} class="text-xs text-base-content/60">{@sub}</div>
      <div :if={@breakdown != []} class="mt-2 pt-2 border-t border-base-300/70 space-y-0.5">
        <div
          :for={{segment, text} <- @breakdown}
          id={"#{@id}-#{segment}"}
          class="flex flex-wrap items-center gap-x-1.5 text-xs text-base-content/60"
        >
          <span class={["inline-block w-1.5 h-1.5 rounded-full shrink-0", segment_dot_class(segment)]}></span>
          <span class="whitespace-nowrap">{reason_label(segment)}:</span>
          <span class="font-medium tabular-nums text-base-content/90">{text}</span>
        </div>
      </div>
    </div>
    """
  end

  attr(:by, :string, required: true)
  attr(:sort_by, :atom, required: true)
  attr(:sort_dir, :atom, required: true)
  attr(:class, :string, default: nil)
  slot(:inner_block, required: true)

  defp sort_header(assigns) do
    assigns = assign(assigns, :active, Map.get(@sort_keys, assigns.by) == assigns.sort_by)

    ~H"""
    <th class={@class}>
      <button
        type="button"
        id={"sort-#{@by}"}
        phx-click="sort"
        phx-value-by={@by}
        class={[
          "inline-flex items-center gap-1 hover:text-base-content transition-colors",
          @active && "text-base-content"
        ]}
      >
        {render_slot(@inner_block)}
        <.icon
          :if={@active}
          name={if @sort_dir == :asc, do: "hero-chevron-up", else: "hero-chevron-down"}
          class="w-3 h-3"
        />
        <.icon :if={!@active} name="hero-chevron-up-down" class="w-3 h-3 opacity-40" />
      </button>
    </th>
    """
  end

  attr(:now, :integer, default: nil)
  attr(:prev, :integer, default: nil)

  defp usage_trend(assigns) do
    ~H"""
    <span class="inline-flex items-center gap-1 whitespace-nowrap tabular-nums">
      {format_number(@now)}
      <%= cond do %>
        <% is_nil(@prev) or is_nil(@now) -> %>
          <span class="text-base-content/40 text-xs" title="No earlier window to compare">-</span>
        <% @now > @prev -> %>
          <.icon name="hero-arrow-trending-up" class="w-4 h-4 text-success" />
        <% @now < @prev -> %>
          <.icon name="hero-arrow-trending-down" class="w-4 h-4 text-error" />
        <% true -> %>
          <.icon name="hero-minus" class="w-4 h-4 text-base-content/40" />
      <% end %>
      <span :if={@prev} class="text-xs text-base-content/50">
        was {format_number(@prev)}
      </span>
    </span>
    """
  end

  defp sync_running?(job), do: job != nil and job.status == :running

  defp sync_phase_text(%{phase: :fetching}), do: "Reading invoices from Stripe..."
  defp sync_phase_text(%{phase: :writing}), do: "Writing the imported invoices..."
  defp sync_phase_text(_job), do: "Working..."

  defp sync_result_text(result) when is_map(result) do
    counts =
      result
      |> Enum.filter(fn {_key, value} -> is_integer(value) end)
      |> Enum.sort()
      |> Enum.map_join(", ", fn {key, value} ->
        "#{value} #{key |> to_string() |> String.replace("_", " ")}"
      end)

    if counts == "", do: "Import finished.", else: "Import finished: #{counts}."
  end

  defp sync_result_text(_result), do: "Import finished."

  defp coverage_text(gaps) do
    Enum.map_join(gaps, ", ", fn
      {from, from} -> Date.to_iso8601(from)
      {from, to} -> "#{Date.to_iso8601(from)} to #{Date.to_iso8601(to)}"
    end)
  end

  defp list_text(value) when is_list(value), do: Enum.join(value, "\n")
  defp list_text(value) when is_binary(value), do: value
  defp list_text(_value), do: ""

  defp inline_list_text(value) when is_list(value), do: Enum.join(value, ", ")
  defp inline_list_text(value) when is_binary(value), do: value
  defp inline_list_text(_value), do: ""

  defp field_list(form, field) do
    case form[field].value do
      list when is_list(list) -> list
      _ -> []
    end
  end

  # ─── Render ──────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-[1600px] mx-auto">
      <div class="flex flex-wrap items-start justify-between gap-4 mb-2">
        <h1 class="text-3xl font-bold">Business Clients</h1>
        <div class="flex flex-wrap items-center gap-2">
          <.link
            id="export-clients"
            href={export_path("clients")}
            class="btn btn-sm btn-primary"
          >
            <.icon name="hero-arrow-down-tray" class="w-4 h-4" /> Clients CSV
          </.link>
          <.link
            :if={can_edit?(assigns)}
            id="export-business-email-users"
            href={export_path("business_email_users")}
            class="btn btn-sm btn-soft"
          >
            Business-email users CSV
          </.link>
          <.link
            id="export-churned"
            href={export_path("churned")}
            class="btn btn-sm btn-soft"
          >
            Churned CSV
          </.link>
          <.link
            id="export-monthly-metrics"
            href={export_path("monthly_metrics")}
            class="btn btn-sm btn-soft"
          >
            Monthly metrics CSV
          </.link>
          <button id="refresh" type="button" phx-click="refresh" class="btn btn-sm btn-soft">
            <.icon name="hero-arrow-path" class="w-4 h-4" /> Refresh
          </button>
        </div>
      </div>
      <p class="text-sm text-base-content/60 mb-6 max-w-4xl">
        B2B revenue: every user whose paid invoice lines put them on a business plan, or
        on a business-email plan with a company email. Amounts come from the Stripe invoice
        mirror, whatever paid them - card, wire, crypto or SAN. Numbers marked
        <span class="text-primary font-semibold">*</span>
        are explained at the bottom of the page.
      </p>

      <%!-- ── Invoice import ─────────────────────────────────────────── --%>
      <div id="invoice-sync" class="card bg-base-100 border border-base-300 p-4 mb-6">
        <div class="flex flex-wrap items-end justify-between gap-3">
          <div class="text-sm">
            <div>
              <span class="text-base-content/60">Stripe invoices last synced:</span>
              <span id="last-synced-at" class="font-medium">
                {format_datetime(@last_synced_at)}
              </span>
            </div>
            <div class="text-base-content/60 text-xs">
              Re-import a range to fill a gap or pick up invoices changed in Stripe.
            </div>
          </div>

          <.form
            :if={can_edit?(assigns)}
            for={%{}}
            id="resync-form"
            phx-submit="resync"
            class="flex flex-wrap items-end gap-2"
          >
            <.input type="date" name="from" id="resync-from" label="From" value={@resync_from} />
            <.input type="date" name="to" id="resync-to" label="To" value={@resync_to} />
            <div class="flex items-center gap-2 mb-2">
              <button
                id="resync-button"
                type="submit"
                disabled={sync_running?(@sync_job)}
                class="btn btn-sm btn-primary"
              >
                Re-import from Stripe
              </button>
              <button
                :if={sync_running?(@sync_job)}
                id="cancel-sync"
                type="button"
                phx-click="cancel_sync"
                class="btn btn-sm btn-soft btn-error"
              >
                Stop watching
              </button>
            </div>
          </.form>
        </div>

        <div :if={sync_running?(@sync_job)} id="sync-progress" class="mt-3">
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
          <span>{sync_result_text(@sync_job.result)}</span>
        </div>

        <div :if={@sync_job.status == :failed} role="alert" class="alert alert-error mt-3">
          <span>The import failed: {@sync_job.error}</span>
        </div>
      </div>

      <.async_result :let={report} assign={@report}>
        <:loading>
          <div class="flex items-center gap-3 py-10">
            <span class="loading loading-spinner loading-md"></span>
            <span class="text-sm text-base-content/70">Computing business client numbers...</span>
          </div>
        </:loading>

        <:failed :let={reason}>
          <div role="alert" class="alert alert-error mb-6">
            <span>Failed to load the report: {inspect(reason)}</span>
          </div>
        </:failed>

        <div
          :if={report.coverage != []}
          id="coverage-warning"
          role="alert"
          class="alert alert-warning mb-4"
        >
          <span>
            Never imported: {coverage_text(report.coverage)}. Invoices from those days are
            missing from every number below - re-import the range to fill them in.
          </span>
        </div>

        <%!-- ── Headline metrics ──────────────────────────────────────── --%>
        <div class="text-xs text-base-content/60 mb-2">
          As of {format_date(report.metrics.as_of)} · churn and renewal window {format_date(
            report.metrics.window.from
          )} to {format_date(report.metrics.window.to)}
        </div>

        <div id="metric-cards" class="grid grid-cols-2 md:grid-cols-4 2xl:grid-cols-8 gap-4 mb-8">
          <.metric_card
            id="metric-client-count"
            label="Clients"
            value={format_number(report.metrics.client_count)}
            sub="business clients today"
            note={:business_client}
            notes={@notes}
            breakdown={breakdown(report.metrics, :client_count)}
          />
          <.metric_card
            id="metric-mrr"
            label="MRR"
            value={money(report.metrics.mrr)}
            sub={"ARR #{money(report.metrics.mrr && report.metrics.mrr * 12)}"}
            note={:mrr}
            notes={@notes}
            breakdown={breakdown(report.metrics, :mrr)}
          />
          <.metric_card
            id="metric-at-risk"
            label="At risk"
            value={format_number(report.metrics.at_risk_count)}
            sub="open At Risk / High Risk entries"
            note={:at_risk}
            notes={@notes}
            breakdown={breakdown(report.metrics, :at_risk_count)}
            accent={report.metrics.at_risk_count > 0 && "text-warning"}
          />
          <.metric_card
            id="metric-retention"
            label="With retention action"
            value={percent(report.metrics.retention_action_pct)}
            sub="of at-risk clients"
            note={:retention}
            notes={@notes}
            breakdown={breakdown(report.metrics, :retention_action_pct)}
          />
          <.metric_card
            id="metric-client-churn"
            label="Client churn"
            value={rate(report.metrics.client_churn.rate)}
            sub={"#{report.metrics.client_churn.lost} lost of #{report.metrics.client_churn.base}"}
            note={:client_churn}
            notes={@notes}
            breakdown={breakdown(report.metrics, :client_churn)}
          />
          <.metric_card
            id="metric-revenue-churn"
            label="Revenue churn"
            value={rate(report.metrics.revenue_churn.rate)}
            sub={"#{money(report.metrics.revenue_churn.lost_mrr)} of #{money(report.metrics.revenue_churn.base_mrr)} MRR, +#{money(report.metrics.revenue_churn.expansion_mrr)} expansion"}
            note={:revenue_churn}
            notes={@notes}
            breakdown={breakdown(report.metrics, :revenue_churn)}
          />
          <.metric_card
            id="metric-client-renewal"
            label="Client renewal"
            value={rate(report.metrics.client_renewal.rate)}
            sub={"#{report.metrics.client_renewal.renewed} renewed of #{report.metrics.client_renewal.due} due"}
            note={:client_renewal}
            notes={@notes}
            breakdown={breakdown(report.metrics, :client_renewal)}
          />
          <.metric_card
            id="metric-revenue-renewal"
            label="Revenue renewal"
            value={rate(report.metrics.revenue_renewal.rate)}
            sub={"#{money(report.metrics.revenue_renewal.renewed_acv)} of #{money(report.metrics.revenue_renewal.due_acv)} ACV"}
            note={:revenue_renewal}
            notes={@notes}
            breakdown={breakdown(report.metrics, :revenue_renewal)}
          />
        </div>

        <%!-- ── Clients ───────────────────────────────────────────────── --%>
        <h2 class="text-xl font-semibold mb-2">Clients</h2>

        <div class="card bg-base-100 border border-base-300 p-4 mb-4">
          <.form
            for={%{}}
            id="client-filters"
            phx-change="filter"
            phx-submit="filter"
            class="flex flex-wrap items-end gap-4"
          >
            <.input
              type="text"
              name="query"
              id="filter-query"
              label="Search"
              value={@filters.query}
              placeholder="email, username, customer id"
              phx-debounce="300"
              outer_div_class="w-72"
            />
            <.input
              type="select"
              name="plan"
              id="filter-plan"
              label="Plan"
              value={@filters.plan}
              options={@plan_options}
              outer_div_class="w-44"
            />
            <.input
              type="select"
              name="status"
              id="filter-status"
              label="Manual status"
              value={@filters.status}
              options={[{"Any status", :all} | Enum.map(statuses(), &{status_label(&1), &1})]}
              outer_div_class="w-40"
            />
            <.input
              type="select"
              name="reason"
              id="filter-reason"
              label="Business because"
              value={@filters.reason}
              options={[{"Any reason", :all} | Enum.map(reasons(), &{reason_label(&1), &1})]}
              outer_div_class="w-44"
            />
            <.input
              type="number"
              name="renewal_within"
              id="filter-renewal-within"
              label="Renews within (days)"
              value={@filters.renewal_within}
              min="0"
              placeholder="any"
              phx-debounce="300"
              outer_div_class="w-40"
            />
            <button
              id="clear-filters"
              type="button"
              phx-click="clear_filters"
              class="btn btn-sm btn-ghost mb-2"
            >
              Clear
            </button>
          </.form>
        </div>

        <.clients_table
          rows={@streams.clients}
          count={@visible_count}
          total={@client_total}
          sort_by={@sort_by}
          sort_dir={@sort_dir}
          today={@today}
          renewal_intervals={@settings.renewal_intervals}
          can_edit={can_edit?(assigns)}
        />

        <%!-- ── Recently churned ──────────────────────────────────────── --%>
        <.churned_table
          rows={@streams.churned}
          count={@churned_count}
          lost_mrr={@churned_lost_mrr}
          notes={@notes}
          window_months={@settings.churn_window_months}
        />
      </.async_result>

      <%!-- ── Monthly ───────────────────────────────────────────────── --%>
      <h2 class="text-xl font-semibold mb-2">Month by month</h2>
      <p class="text-sm text-base-content/60 mb-2">
        Each month as of its first day. Snapshot months were frozen when the month
        started, so the log state and usage stay as they were reported; computed months
        are recomputed from the invoice mirror with the current settings.
      </p>

      <.async_result :let={report} assign={@report}>
        <:loading>
          <div class="flex items-center gap-3 py-6">
            <span class="loading loading-spinner loading-sm"></span>
            <span class="text-sm text-base-content/70">Computing the monthly numbers...</span>
          </div>
        </:loading>
        <:failed :let={reason}>
          <div role="alert" class="alert alert-error mb-6">
            <span>Failed to load the monthly numbers: {inspect(reason)}</span>
          </div>
        </:failed>

        <div
          id="monthly-segment"
          role="group"
          aria-label="Segment"
          class="inline-flex gap-0.5 rounded-lg border border-base-300 bg-base-100 p-0.5 mb-2"
        >
          <button
            :for={segment <- [:total | segments()]}
            id={"monthly-segment-#{segment}"}
            type="button"
            phx-click="monthly_segment"
            phx-value-segment={segment}
            aria-pressed={to_string(@monthly_segment == segment)}
            class={[
              "inline-flex items-center gap-1.5 px-3 py-1 text-xs font-medium rounded-md transition-colors duration-150",
              if(@monthly_segment == segment,
                do: "bg-base-content text-base-100 shadow-sm",
                else: "text-base-content/70 hover:bg-base-200 hover:text-base-content"
              )
            ]}
          >
            <span
              :if={segment != :total}
              class={["inline-block w-1.5 h-1.5 rounded-full", segment_dot_class(segment)]}
            ></span>
            {reason_label(segment)}
          </button>
        </div>

        <div class="rounded-box border border-base-300 overflow-x-auto mb-8">
          <table id="monthly-metrics" class="table table-zebra table-sm">
            <thead>
              <tr>
                <th>Month</th>
                <th>Source</th>
                <th class="text-right">
                  Clients<.note_mark key={:business_client} notes={@notes} />
                </th>
                <th class="text-right">MRR<.note_mark key={:mrr} notes={@notes} /></th>
                <th class="text-right">At risk<.note_mark key={:at_risk} notes={@notes} /></th>
                <th class="text-right">Retention<.note_mark key={:retention} notes={@notes} /></th>
                <th class="text-right">
                  Client churn<.note_mark key={:client_churn} notes={@notes} />
                </th>
                <th class="text-right">
                  Revenue churn<.note_mark key={:revenue_churn} notes={@notes} />
                </th>
                <th class="text-right">
                  Client renewal<.note_mark key={:client_renewal} notes={@notes} />
                </th>
                <th class="text-right">
                  Revenue renewal<.note_mark key={:revenue_renewal} notes={@notes} />
                </th>
              </tr>
            </thead>
            <tbody>
              <tr :if={report.monthly == []}>
                <td colspan="10" class="text-center text-base-content/60 py-6">
                  No monthly numbers yet.
                </td>
              </tr>
              <tr
                :for={{m, v} <- monthly_rows(report.monthly, @monthly_segment)}
                id={"month-#{m.month}"}
              >
                <td class="font-medium whitespace-nowrap">{Calendar.strftime(m.month, "%Y-%m")}</td>
                <td>
                  <span
                    class={[
                      "badge badge-xs",
                      if(m.source == :snapshot, do: "badge-info badge-soft", else: "badge-ghost")
                    ]}
                    title={
                      if m.source == :snapshot,
                        do: "Frozen on the first day of the month",
                        else: "Recomputed now from the invoice mirror"
                    }
                  >
                    {m.source}
                  </span>
                </td>
                <%= if v do %>
                  <td class="text-right tabular-nums">{format_number(v.client_count)}</td>
                  <td class="text-right tabular-nums">{money(v.mrr)}</td>
                  <td class="text-right tabular-nums">{format_number(v.at_risk_count)}</td>
                  <td class="text-right tabular-nums">{percent(v.retention_action_pct)}</td>
                  <td class="text-right tabular-nums">
                    {rate(v.client_churn.rate)}
                    <span class="text-xs text-base-content/50">
                      ({v.client_churn.lost}/{v.client_churn.base})
                    </span>
                  </td>
                  <td class="text-right tabular-nums">
                    {rate(v.revenue_churn.rate)}
                    <span class="text-xs text-base-content/50">
                      ({money(v.revenue_churn.lost_mrr)}/{money(v.revenue_churn.base_mrr)})
                    </span>
                  </td>
                  <td class="text-right tabular-nums">
                    {rate(v.client_renewal.rate)}
                    <span class="text-xs text-base-content/50">
                      ({v.client_renewal.renewed}/{v.client_renewal.due})
                    </span>
                  </td>
                  <td class="text-right tabular-nums">
                    {rate(v.revenue_renewal.rate)}
                    <span class="text-xs text-base-content/50">
                      ({money(v.revenue_renewal.renewed_acv)}/{money(v.revenue_renewal.due_acv)})
                    </span>
                  </td>
                <% else %>
                  <td
                    :for={_column <- 1..8}
                    class="text-right text-base-content/50"
                    title="Snapshot taken before the segment split"
                  >
                    -
                  </td>
                <% end %>
              </tr>
            </tbody>
          </table>
        </div>
      </.async_result>

      <%!-- ── Settings ──────────────────────────────────────────────── --%>
      <.settings_panel
        form={@settings_form}
        last_change={@settings_last_change}
        open={@settings_open}
        editing={@settings_editing}
        owner={owner?(assigns)}
      />

      <.formula_notes notes={@notes} open={@notes_open} />
    </div>
    """
  end

  attr(:rows, :any, required: true, doc: "the `:clients` stream")
  attr(:count, :integer, required: true)
  attr(:total, :integer, required: true)
  attr(:sort_by, :atom, required: true)
  attr(:sort_dir, :atom, required: true)
  attr(:today, Date, required: true)
  attr(:renewal_intervals, :list, required: true)
  attr(:can_edit, :boolean, default: false)

  defp clients_table(assigns) do
    ~H"""
    <div id="clients-count" class="text-sm text-base-content/60 mb-2">
      Showing {@count} of {@total} client(s). {renewal_hint(@renewal_intervals)}
    </div>
    <div class="rounded-box border border-base-300 overflow-x-auto mb-8">
      <table id="clients-table" class="table table-zebra table-sm">
        <thead>
          <tr>
            <th>Client</th>
            <th>Plan</th>
            <th>Business because</th>
            <.sort_header by="mrr" sort_by={@sort_by} sort_dir={@sort_dir} class="text-right">
              MRR
            </.sort_header>
            <.sort_header by="acv" sort_by={@sort_by} sort_dir={@sort_dir} class="text-right">
              ACV
            </.sort_header>
            <th class="text-right">TCV</th>
            <th>Start</th>
            <.sort_header by="renewal_date" sort_by={@sort_by} sort_dir={@sort_dir}>
              Renewal
            </.sort_header>
            <th>Paid by</th>
            <th>API calls</th>
            <th>Last active</th>
            <th>Status</th>
            <th class="text-right">Open</th>
            <th :if={@can_edit}><span class="sr-only">Actions</span></th>
          </tr>
        </thead>
        <tbody id="clients-rows" phx-update="stream">
          <tr id="clients-empty" class="hidden only:table-row">
            <td colspan={if @can_edit, do: 14, else: 13} class="text-center text-base-content/60 py-6">
              No client matches these filters.
            </td>
          </tr>
          <tr
            :for={{dom_id, c} <- @rows}
            id={dom_id}
            class="hover:bg-base-200 transition-colors"
          >
            <td class="max-w-64">
              <.link
                navigate={~p"/admin/business_clients/#{c.user_id}"}
                class="link link-primary font-medium break-all"
              >
                {c.email || c.username || "user ##{c.user_id}"}
              </.link>
              <.stripe_customer_link
                id={"stripe-customer-#{c.user_id}"}
                customer_id={c.stripe_customer_id}
              />
              <div :if={c.username && c.email} class="text-xs text-base-content/60">
                {c.username}
              </div>
            </td>
            <td class="whitespace-nowrap">
              <div class="font-medium">{c.plan_name}</div>
              <div class="text-xs text-base-content/60">
                {c.interval}{if c.subscription_status, do: " · #{c.subscription_status}"}
              </div>
            </td>
            <td><.reason_badge reason={c.business_reason} override={c.override} /></td>
            <td class="text-right tabular-nums font-medium">{money(c.mrr)}</td>
            <td class="text-right tabular-nums">{money(c.acv)}</td>
            <td class="text-right tabular-nums text-base-content/70">{money(c.tcv)}</td>
            <td class="whitespace-nowrap">{format_date(c.start_date)}</td>
            <td class="whitespace-nowrap">
              <span
                :if={renewal_highlight?(c, @renewal_intervals, @today)}
                class="badge badge-sm badge-warning"
                title="Renews within 30 days"
              >
                {format_date(c.renewal_date)}
              </span>
              <span :if={!renewal_highlight?(c, @renewal_intervals, @today)}>
                {format_date(c.renewal_date)}
              </span>
            </td>
            <td>
              <div class="flex flex-wrap gap-1 max-w-56">
                <span
                  :for={{source, amount} <- paid_by_mix(c.paid_by)}
                  class={["badge badge-xs whitespace-nowrap", paid_by_badge_class(source)]}
                >
                  {paid_by_label(source)}: {money(amount)}
                </span>
                <span
                  :if={c.failed_payment?}
                  class="badge badge-xs badge-error whitespace-nowrap"
                  title="The business subscription is past due or unpaid: a charge failed"
                >
                  <.icon name="hero-exclamation-triangle" class="w-3 h-3" /> payment failed
                </span>
                <span
                  :if={c.unpaid_invoice?}
                  class="badge badge-xs badge-warning badge-soft whitespace-nowrap"
                  title="A business invoice has been open for more than 7 days - e.g. a wire or crypto payment not received yet"
                >
                  <.icon name="hero-clock" class="w-3 h-3" /> unpaid invoice
                </span>
              </div>
            </td>
            <td><.usage_trend now={c.api_calls} prev={c.api_calls_prev} /></td>
            <td class="whitespace-nowrap text-base-content/70">
              {format_datetime(c.last_active_at)}
              <span
                :if={activity_source(c)}
                class="badge badge-xs badge-ghost ml-1"
                title={"Last web session: #{format_datetime(c.last_web_active_at)}, last API call: #{format_datetime(c.last_api_call_at)}"}
              >
                {activity_source(c)}
              </span>
            </td>
            <td>
              <span class="inline-flex items-center gap-1">
                <.status_badge status={c.manual_status} />
                <.icon
                  :if={c.retention_action?}
                  name="hero-lifebuoy"
                  class="w-4 h-4 text-info"
                />
              </span>
            </td>
            <td class="text-right tabular-nums">
              <span :if={c.open_entries_count > 0} class="badge badge-sm badge-neutral">
                {c.open_entries_count}
              </span>
              <span :if={c.open_entries_count == 0} class="text-base-content/40">0</span>
            </td>
            <td :if={@can_edit} class="text-right">
              <.link
                id={"log-client-#{c.user_id}"}
                navigate={~p"/admin/business_clients/#{c.user_id}" <> "#add-entry-panel"}
                class="btn btn-xs btn-ghost gap-1 opacity-70 hover:opacity-100 transition-opacity"
                title="Add a log entry, e.g. mark the client At Risk"
              >
                <.icon name="hero-pencil-square" class="w-3.5 h-3.5" /> Log
              </.link>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  attr(:rows, :any, required: true, doc: "the `:churned` stream")
  attr(:count, :integer, required: true)
  attr(:lost_mrr, :integer, required: true)
  attr(:notes, :map, required: true)
  attr(:window_months, :integer, required: true)

  defp churned_table(assigns) do
    ~H"""
    <div class="flex flex-wrap items-baseline gap-x-3 gap-y-1 mb-2">
      <h2 id="churned-heading" class="text-xl font-semibold">
        Recently churned<.note_mark key={:churned} notes={@notes} />
      </h2>
      <span id="churned-summary" class="text-sm text-base-content/60">
        {@count} client(s) in the last {@window_months} months ·
        <span class="font-medium text-error">{money(@lost_mrr)}</span>
        MRR lost
      </span>
    </div>
    <div class="rounded-box border border-base-300 overflow-x-auto mb-8">
      <table id="churned-table" class="table table-zebra table-sm">
        <thead>
          <tr>
            <th>Client</th>
            <th>Business because</th>
            <th>Last plan</th>
            <th>Joined</th>
            <th>Churned on</th>
            <th class="text-right">Lost MRR</th>
            <th class="text-right">TCV</th>
            <th>Now on</th>
            <th>Last log entry</th>
          </tr>
        </thead>
        <tbody id="churned-rows" phx-update="stream">
          <tr id="churned-empty" class="hidden only:table-row">
            <td colspan="9" class="text-center text-base-content/60 py-6">
              No client churned in the window.
            </td>
          </tr>
          <tr
            :for={{dom_id, c} <- @rows}
            id={dom_id}
            class="hover:bg-base-200 transition-colors"
          >
            <td class="max-w-64">
              <.link
                navigate={~p"/admin/business_clients/#{c.user_id}"}
                class="link link-primary font-medium break-all"
              >
                {c.email || c.username || "user ##{c.user_id}"}
              </.link>
              <.stripe_customer_link
                id={"churned-stripe-customer-#{c.user_id}"}
                customer_id={c.stripe_customer_id}
              />
              <div :if={c.username && c.email} class="text-xs text-base-content/60">
                {c.username}
              </div>
            </td>
            <td><.reason_badge reason={c.business_reason} /></td>
            <td class="whitespace-nowrap">
              <div class="font-medium">{c.last_plan_name}</div>
              <div class="text-xs text-base-content/60">{c.interval}</div>
            </td>
            <td class="whitespace-nowrap">{format_date(c.joined_on)}</td>
            <td class="whitespace-nowrap font-medium">{format_date(c.churned_on)}</td>
            <td class="text-right tabular-nums font-medium text-error">{money(c.lost_mrr)}</td>
            <td class="text-right tabular-nums text-base-content/70">{money(c.tcv)}</td>
            <td>
              <span
                :if={c.current_subscription}
                id={"churned-now-on-#{c.user_id}"}
                class="badge badge-sm badge-success badge-soft whitespace-nowrap"
                title="Still paying elsewhere: a current subscription outside the business plans"
              >
                {c.current_subscription}
              </span>
              <span :if={!c.current_subscription} class="text-base-content/40">-</span>
            </td>
            <td class="max-w-80">
              <div :if={c.last_entry}>
                <span class="badge badge-xs badge-ghost whitespace-nowrap">
                  {c.last_entry.type}
                </span>
                <span :if={c.last_entry.note} class="text-xs text-base-content/70">
                  {c.last_entry.note}
                </span>
              </div>
              <span :if={!c.last_entry} class="text-base-content/40">-</span>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  attr(:form, Phoenix.HTML.Form, required: true)
  attr(:last_change, :map, default: nil)
  attr(:open, :boolean, default: false)
  attr(:editing, :boolean, default: false)
  attr(:owner, :boolean, default: false)

  # Collapsed by default and read-only: the inputs sit in a disabled fieldset until an
  # owner presses Edit. Saving is checked against the Owner role again on the server.
  defp settings_panel(assigns) do
    ~H"""
    <details
      id="settings-section"
      open={@open}
      class="group card bg-base-100 border border-base-300 p-4 mb-8"
    >
      <summary
        id="settings-toggle"
        phx-click="toggle_section"
        phx-value-section="settings"
        class="flex items-center gap-2 cursor-pointer list-none select-none hover:text-primary transition-colors [&::-webkit-details-marker]:hidden"
      >
        <.icon
          name="hero-chevron-right"
          class="w-4 h-4 transition-transform duration-200 group-open:rotate-90"
        />
        <span class="text-xl font-semibold">Settings</span>
        <span
          :if={!@editing}
          id="settings-read-only"
          class="badge badge-xs badge-ghost ml-1"
        >
          read-only
        </span>
        <span :if={@editing} class="badge badge-xs badge-warning badge-soft ml-1">editing</span>
      </summary>

      <p class="text-sm text-base-content/60 my-3">
        The parameters behind every number on this page. A change applies to all computed
        months at once; snapshot months keep the settings they were frozen with. Lists take
        one value per line or comma separated.
        <span :if={@last_change} id="settings-last-change">
          Last changed {format_datetime(@last_change.updated_at)}{if @last_change.by,
            do: " by #{@last_change.by}"}.
        </span>
        <span :if={is_nil(@last_change)} id="settings-last-change">
          The defaults apply - nobody has changed them yet.
        </span>
        <span :if={!@owner}>Only an Owner can change them.</span>
      </p>

      <.form
        for={@form}
        id="settings-form"
        phx-change="validate_settings"
        phx-submit="save_settings"
      >
        <fieldset id="settings-fields" disabled={!@editing} class="disabled:opacity-80">
          <div class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-x-6">
            <.input
              field={@form[:business_plan_patterns]}
              type="textarea"
              label="Business plans (a trailing * matches a prefix)"
              value={list_text(@form[:business_plan_patterns].value)}
            />
            <.input
              field={@form[:business_email_plan_names]}
              type="textarea"
              label="Plans that need a business email"
              value={list_text(@form[:business_email_plan_names].value)}
            />
            <.input
              field={@form[:free_email_domains]}
              type="textarea"
              label="Free email domains"
              value={list_text(@form[:free_email_domains].value)}
            />
            <.input
              field={@form[:issue_types]}
              type="textarea"
              label="Log entry types"
              value={list_text(@form[:issue_types].value)}
            />
            <.input
              field={@form[:types_without_severity]}
              type="textarea"
              label="Types without severity"
              value={list_text(@form[:types_without_severity].value)}
            />
            <div>
              <.input
                field={@form[:business_email_product_ids]}
                type="text"
                label="Business-email product ids"
                value={inline_list_text(@form[:business_email_product_ids].value)}
              />
              <.input
                field={@form[:renewal_intervals]}
                type="text"
                label="Renewal intervals (month, year)"
                value={inline_list_text(@form[:renewal_intervals].value)}
              />
              <.input
                field={@form[:retention_action_type]}
                type="select"
                label="Retention action type"
                options={field_list(@form, :issue_types)}
              />
            </div>
            <.input
              field={@form[:churn_window_months]}
              type="number"
              label="Churn window (months)"
              min="1"
              max="36"
            />
            <.input
              field={@form[:renewal_grace_days]}
              type="number"
              label="Renewal grace (days)"
              min="0"
            />
            <.input
              field={@form[:usage_window_days]}
              type="number"
              label="API usage window (days)"
              min="1"
            />
            <.input
              field={@form[:renewal_upgrades_full_value]}
              type="checkbox"
              label="An upgrade at renewal counts its full value as renewed"
            />
          </div>
        </fieldset>

        <div :if={@owner} class="flex items-center gap-2 mt-2">
          <button
            :if={!@editing}
            id="edit-settings"
            type="button"
            phx-click="edit_settings"
            class="btn btn-sm btn-soft"
          >
            <.icon name="hero-pencil-square" class="w-4 h-4" /> Edit
          </button>
          <button :if={@editing} id="save-settings" type="submit" class="btn btn-sm btn-primary">
            Save settings
          </button>
          <button
            :if={@editing}
            id="cancel-settings"
            type="button"
            phx-click="cancel_settings"
            class="btn btn-sm btn-ghost"
          >
            Cancel
          </button>
        </div>
      </.form>
    </details>
    """
  end
end
