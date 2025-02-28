defmodule SanbaseWeb.MetricRegistryChangeSuggestionsLive do
  use SanbaseWeb, :live_view

  alias SanbaseWeb.AdminFormsComponents
  alias Sanbase.Metric.Registry.Permissions
  alias Sanbase.Metric.Registry.ChangeSuggestion
  alias SanbaseWeb.AvailableMetricsComponents

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Metric Registry | Change Requests",
       rows: list_all_submissions(),
       form: to_form(%{})
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <h1 class="text-blue-700 text-2xl mb-4">
        Metric Registry Change Requests
      </h1>
      <SanbaseWeb.MetricRegistryComponents.user_details
        current_user={@current_user}
        current_user_role_names={@current_user_role_names}
      />
      <AvailableMetricsComponents.available_metrics_button
        text="Back to Metric Registry"
        href={~p"/admin2/metric_registry"}
        icon="hero-home"
      />
      <div class="flex-1 p:2 sm:p-6 justify-evenly">
        <.table id="metric_registry_changes_suggestions" rows={@rows}>
          <:col :let={row} label="Status">
            <AdminFormsComponents.status status={row.status} />
          </:col>
          <:col :let={row} label="Metric" col_class="max-w-[320px] break-words">
            <.link
              :if={row.metric_registry_id}
              class="underline text-blue-600"
              href={~p"/admin2/metric_registry/show/#{row.metric_registry_id}"}
              target="_blank"
            >
              {row.metric_registry.metric}
            </.link>
            <span :if={!row.metric_registry_id} class="text-sm font-bold text-green-800">
              NEW METRIC
            </span>
          </:col>
          <:col :let={row} label="Changes"><.formatted_changes row={row} /></:col>
          <:col :let={row} label="Notes">{row.notes}</:col>
          <:col :let={row} label="Submitted By">{row.submitted_by}</:col>
          <:action :let={row}>
            <.action_buttons
              :if={Permissions.can?(:apply_change_suggestions, roles: @current_user_role_names)}
              form={@form}
              row={row}
              current_user={@current_user}
            />
          </:action>
        </.table>
      </div>
    </div>
    """
  end

  def formatted_changes(assigns) do
    ~H"""
    {Sanbase.ExAudit.Patch.format_patch(%{patch: @row.changes})}
    """
  end

  def action_buttons(assigns) do
    ~H"""
    <.form
      for={@form}
      phx-submit="take_action"
      class="flex flex-col lg:flex-row space-y-2 lg:space-y-0 md:space-x-2"
    >
      <input type="hidden" name="record_id" value={@row.id} />
      <input type="hidden" name="metric_registry_id" value={@row.metric_registry_id} />
      <input type="hidden" name="change_request_submitter_email" value={@row.submitted_by} />

      <.action_button
        value="approve"
        text="Approve"
        disabled={@row.status != "pending_approval"}
        colors="bg-green-600 hover:bg-green-800"
      />
      <.action_button
        value="decline"
        text="Decline"
        disabled={@row.status != "pending_approval"}
        colors="bg-red-600 hover:bg-red-800"
      />
      <.action_button
        value="undo"
        text={undo_text(@row.status)}
        disabled={
          # Undo is disabled if it's still in pending state or
          # if the change request is for adding a new metric and it is approved
          # metrics cannot be deleted by undoing the change here
          @row.status == "pending_approval" or
            (@row.status == "approved" and @row.metric_registry_id == nil)
        }
        colors="bg-amber-600 hover:bg-amber-800"
      />

      <.action_button
        :if={@row.status == "pending_approval" and @row.submitted_by == @current_user.email}
        disabled={false}
        value="edit"
        text="Edit"
        colors="bg-fuchsia-600 hover:bg-fuchsia-800"
      />
    </.form>
    """
  end

  defp undo_text("approved"), do: "Undo Approval"
  defp undo_text("declined"), do: "Undo Refusal"
  defp undo_text("pending_approval"), do: "Undo"

  def action_button(assigns) do
    ~H"""
    <AdminFormsComponents.button
      name="action"
      value={@value}
      class={if @disabled, do: "bg-gray-300", else: @colors}
      disabled={@disabled}
      display_text={@text}
    />
    """
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
      nil ->
        {:noreply,
         socket
         |> push_navigate(
           to: ~p"/admin2/metric_registry/new?update_change_request_id=#{record_id}"
         )}

      _ ->
        {:noreply,
         socket
         |> push_navigate(
           to:
             ~p"/admin2/metric_registry/edit/#{metric_registry_id}?update_change_request_id=#{record_id}"
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
          update_assigns_row(socket.assigns.rows, record_id, record.status)

        socket =
          socket
          |> assign(:rows, rows)
          |> put_flash(:info, "Successfully reverted the approved suggested changes!")

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, add_changeset_error_flash(socket, changeset)}
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
        rows = update_assigns_row(socket.assigns.rows, record_id, status)

        socket =
          socket
          |> assign(:rows, rows)
          |> put_flash(:info, "Successfully #{status} the suggested changes!")

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, add_changeset_error_flash(socket, changeset)}
    end
  end

  defp add_changeset_error_flash(socket, changeset_or_error) do
    error_msg =
      case changeset_or_error do
        %Ecto.Changeset{} = changeset ->
          Sanbase.Utils.ErrorHandling.changeset_errors_string(changeset)

        error when is_binary(error) ->
          error
      end

    socket
    |> put_flash(:error, "Error accepting the suggested changes.\n Reason: #{error_msg}!")
  end

  defp update_assigns_row(rows, record_id, status) do
    rows
    |> Enum.map(fn
      %{id: ^record_id} = record -> Map.put(record, :status, status)
      record -> record
    end)
    |> order_records()
  end

  defp list_all_submissions() do
    ChangeSuggestion.list_all_submissions()
    |> Enum.map(&Map.from_struct/1)
    |> Enum.map(
      &Map.update!(&1, :changes, fn encoded -> ChangeSuggestion.decode_changes(encoded) end)
    )
    |> order_records()
  end

  @status_order %{"pending_approval" => 3, "approved" => 2, "declined" => 1}
  defp order_records(handles) do
    handles
    |> Enum.sort_by(&{@status_order[&1.status], &1.id}, :desc)
  end
end
