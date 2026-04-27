defmodule SanbaseWeb.MetricRegistryChangeSuggestionsLive do
  use SanbaseWeb, :live_view

  import SanbaseWeb.AdminLiveHelpers,
    only: [order_records_by_status: 1, put_changeset_error_flash: 3, update_row_by_id: 3]

  alias SanbaseWeb.AdminSharedComponents
  alias Sanbase.Metric.Registry.Permissions
  alias Sanbase.Metric.Registry.ChangeSuggestion

  @impl true
  def mount(_params, _session, socket) do
    rows = list_all_submissions()
    selected_tab = "pending_approval"

    {:ok,
     socket
     |> assign(
       page_title: "Metric Registry | Change Requests",
       rows: rows,
       users:
         Enum.map(rows, & &1.submitted_by) |> Enum.uniq() |> Enum.reject(&is_nil/1) |> Enum.sort(),
       selected_tab: selected_tab,
       filters: %{},
       current_user_only: false,
       form: to_form(%{})
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <AdminSharedComponents.page_header
        title="Metric Registry Change Requests"
        current_user={@current_user}
        current_user_role_names={@current_user_role_names}
        trim_role_prefix="Metric Registry "
      />
      <AdminSharedComponents.nav_button
        text="Back to Metric Registry"
        href={~p"/admin/metric_registry"}
        icon="hero-home"
      />
      <.filters users={@users} filters={@filters} />
      <.tabs rows={@rows} selected_tab={@selected_tab} filters={@filters} />
      <div class="flex-1 p-2 sm:p-6 justify-evenly">
        <.table
          id="metric_registry_changes_suggestions"
          rows={visible_rows(@rows, @selected_tab, @filters)}
        >
          <:col :let={row} label="Status">
            <AdminSharedComponents.status_badge status={row.status} />
          </:col>
          <:col :let={row} label="Metric" col_class="max-w-[320px] break-words">
            <.link
              :if={row.metric_registry_id}
              class="link link-primary"
              href={~p"/admin/metric_registry/show/#{row.metric_registry_id}"}
              target="_blank"
            >
              {row.metric_registry.metric}
            </.link>
            <span :if={!row.metric_registry_id} class="badge badge-sm badge-success badge-soft">
              NEW METRIC
            </span>
          </:col>
          <:col :let={row} label="Changes">
            <.formatted_changes is_new_metric={!row.metric_registry_id} changes={row.changes} />
          </:col>
          <:col :let={row} label="Date">
            <.request_dates inserted_at={row.inserted_at} updated_at={row.updated_at} />
          </:col>
          <:col :let={row} label="Notes">{row.notes}</:col>
          <:col :let={row} label="Submitted By">{row.submitted_by}</:col>
          <:action :let={row}>
            <.action_buttons
              :if={Permissions.can?(:apply_change_suggestions, roles: @current_user_role_names)}
              form={@form}
              row={row}
              current_user={@current_user}
              current_user_role_names={@current_user_role_names}
            />
          </:action>
        </.table>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("apply_filters", %{"only_submitted_by" => email}, socket) do
    {:noreply,
     assign(socket, filters: Map.put(socket.assigns.filters, :only_submitted_by, email))}
  end

  @impl true
  def handle_event("select_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, selected_tab: tab)}
  end

  @impl true
  def handle_event(
        "take_action",
        %{
          "action" => "edit",
          "record_id" => record_id,
          "metric_registry_id" => metric_registry_id,
          "change_request_submitter_email" => submitted_by_email
        },
        socket
      ) do
    Permissions.can?(:edit_change_suggestion,
      roles: socket.assigns.current_user_role_names,
      user_email: socket.assigns.current_user.email,
      submitter_email: submitted_by_email
    )

    case metric_registry_id do
      none when none in [nil, ""] ->
        {:noreply,
         socket
         |> push_navigate(
           to: ~p"/admin/metric_registry/new?update_change_request_id=#{record_id}"
         )}

      _ ->
        {:noreply,
         socket
         |> push_navigate(
           to:
             ~p"/admin/metric_registry/edit/#{metric_registry_id}?update_change_request_id=#{record_id}"
         )}
    end
  end

  @impl true
  def handle_event("take_action", %{"action" => "undo", "record_id" => record_id}, socket) do
    Permissions.raise_if_cannot(:apply_change_suggestions,
      roles: socket.assigns.current_user_role_names
    )

    record_id = String.to_integer(record_id)

    case ChangeSuggestion.undo(record_id) do
      {:ok, record} ->
        rows =
          update_row_by_id(socket.assigns.rows, record_id, %{status: record.status})

        socket =
          socket
          |> assign(:rows, rows)
          |> put_flash(:info, "Successfully reverted the approved suggested changes!")

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply,
         put_changeset_error_flash(socket, changeset, "Error reverting the suggested changes")}
    end
  end

  @impl true
  def handle_event(
        "take_action",
        %{"action" => action, "record_id" => record_id},
        socket
      )
      when action in ["approve", "decline"] do
    status = action <> "d"

    Permissions.raise_if_cannot(:apply_change_suggestions,
      roles: socket.assigns.current_user_role_names
    )

    record_id = String.to_integer(record_id)

    case Sanbase.Metric.Registry.ChangeSuggestion.update_status(record_id, status) do
      {:ok, _} ->
        rows = update_row_by_id(socket.assigns.rows, record_id, %{status: status})

        socket =
          socket
          |> assign(:rows, rows)
          |> put_flash(:info, "Successfully #{status} the suggested changes!")

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply,
         put_changeset_error_flash(
           socket,
           changeset,
           "Error #{action}ing the suggested changes"
         )}
    end
  end

  defp visible_rows(rows, tab, filters) do
    rows
    |> Enum.filter(fn row -> row.status == tab end)
    |> maybe_apply_filter(:only_submitted_by, filters)
  end

  defp maybe_apply_filter(rows, :only_submitted_by, %{only_submitted_by: "all"}), do: rows

  defp maybe_apply_filter(rows, :only_submitted_by, %{only_submitted_by: email}) do
    Enum.filter(rows, fn row -> row.submitted_by == email end)
  end

  defp maybe_apply_filter(rows, _filter, _filters), do: rows

  defp formatted_changes(assigns) do
    ~H"""
    <div>
      <div :if={@is_new_metric and no_docs?(@changes)} class="text-2xl font-bold text-error mb-2">
        MISSING DOCUMENTATION
      </div>
      <div>
        {Sanbase.ExAudit.Patch.format_patch(%{patch: @changes})}
      </div>
    </div>
    """
  end

  defp no_docs?(changes) do
    not Map.has_key?(changes, :docs)
  end

  defp request_dates(assigns) do
    ~H"""
    <div class="flex flex-col">
      <div class="text-nowrap">
        <span class="text-success font-bold">Created</span> {Sanbase.Utils.DateTime.rough_duration_since(
          @inserted_at
        )} ago
      </div>
      <div :if={@inserted_at != @updated_at}>
        <span class="text-warning font-bold">Updated</span> {Sanbase.Utils.DateTime.rough_duration_since(
          @updated_at
        )} ago
      </div>
    </div>
    """
  end

  defp filters(assigns) do
    ~H"""
    <div>
      <form phx-change="apply_filters">
        <.input
          value={@filters["only_submitted_by"] || "all"}
          type="select"
          name="only_submitted_by"
          label="Filter by submitter"
          options={["all"] ++ @users}
        />
      </form>
    </div>
    """
  end

  defp tabs(assigns) do
    ~H"""
    <div role="tablist" class="tabs tabs-border mt-6">
      <.tab
        text="Pending Approval"
        tab="pending_approval"
        is_selected={@selected_tab == "pending_approval"}
        count={length(visible_rows(@rows, "pending_approval", @filters))}
      />
      <.tab
        text="Approved"
        tab="approved"
        is_selected={@selected_tab == "approved"}
        count={length(visible_rows(@rows, "approved", @filters))}
      />
      <.tab
        text="Declined"
        tab="declined"
        is_selected={@selected_tab == "declined"}
        count={length(visible_rows(@rows, "declined", @filters))}
      />
    </div>
    """
  end

  defp tab(assigns) do
    ~H"""
    <span
      role="tab"
      phx-click={JS.push("select_tab", value: %{tab: @tab})}
      class={["tab font-bold", if(@is_selected, do: "tab-active text-primary")]}
    >
      <span>
        {@text} ({@count})
      </span>
    </span>
    """
  end

  defp action_buttons(assigns) do
    ~H"""
    <.form
      for={@form}
      phx-submit="take_action"
      class="flex flex-col lg:flex-row space-y-2 lg:space-y-0 md:space-x-2"
    >
      <input type="hidden" name="record_id" value={@row.id} />
      <input type="hidden" name="metric_registry_id" value={@row.metric_registry_id} />
      <input type="hidden" name="change_request_submitter_email" value={@row.submitted_by} />

      <AdminSharedComponents.approval_button
        name="action"
        value="approve"
        text="Approve"
        disabled={@row.status != "pending_approval"}
        variant="btn-success"
      />
      <AdminSharedComponents.approval_button
        name="action"
        value="decline"
        text="Decline"
        disabled={@row.status != "pending_approval"}
        variant="btn-error"
      />
      <AdminSharedComponents.approval_button
        name="action"
        value="undo"
        text={AdminSharedComponents.undo_text(@row.status)}
        disabled={
          # Undo is disabled if it's still in pending state or
          # if the change request is for adding a new metric and it is approved
          # metrics cannot be deleted by undoing the change here
          @row.status == "pending_approval" or
            (@row.status == "approved" and @row.metric_registry_id == nil)
        }
        variant="btn-warning"
      />

      <AdminSharedComponents.approval_button
        :if={
          @row.status == "pending_approval" and
            Permissions.can?(:edit_change_suggestion,
              roles: @current_user_role_names,
              user_email: @current_user.email,
              submitter_email: @row.submitted_by
            )
        }
        name="action"
        disabled={false}
        value="edit"
        text="Edit"
        variant="btn-secondary"
      />
    </.form>
    """
  end

  defp list_all_submissions() do
    ChangeSuggestion.list_all_submissions()
    |> Enum.map(&Map.from_struct/1)
    |> Enum.map(
      &Map.update!(&1, :changes, fn encoded -> ChangeSuggestion.decode_changes(encoded) end)
    )
    |> order_records_by_status()
  end
end
