defmodule SanbaseWeb.ProjectEcosystemLabelingAdminLive do
  use SanbaseWeb, :live_view

  alias SanbaseWeb.EcosystemComponents
  alias SanbaseWeb.Admin.UserSubmissionAdminComponents

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:rows, list_all_submissions())
     |> assign(:form, to_form(%{}))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="flex-1 p:2 sm:p-6 justify-evenly flex flex-col-reverse scrolling-auto">
        <.table id="ecosystem_changes_suggestions" rows={@rows}>
          <:col :let={row} label="Status">
            <UserSubmissionAdminComponents.status status={row.status} />
          </:col>
          <:col :let={row} label="Asset">
            <.link
              class="underline text-blue-600"
              href={~p"/admin2/generic/#{row.project_id}?resource=projects"}
              target="_blank"
            >
              <%= row.project_name %>
            </.link>
          </:col>
          <:col :let={row} label="Added Ecosystems">
            <EcosystemComponents.ecosystems_group
              ecosystems={row.added_ecosystems}
              ecosystem_colors_class="bg-green-100 text-green-800"
            />
          </:col>
          <:col :let={row} label="Removed Ecosystems">
            <EcosystemComponents.ecosystems_group
              ecosystems={row.removed_ecosystems}
              ecosystem_colors_class="bg-red-100 text-red-800"
            />
          </:col>
          <:col :let={row} label="Notes"><%= row.notes %></:col>
          <:action :let={row}>
            <.form for={@form} phx-submit="update_status">
              <input type="hidden" name="record_id" value={row.id} />
              <UserSubmissionAdminComponents.update_status_button
                name="status"
                value="approved"
                class="bg-green-600 hover:bg-green-800"
                display_text="Approve"
              />
              <UserSubmissionAdminComponents.update_status_button
                name="status"
                value="declined"
                class="bg-red-600 hover:bg-red-800"
                display_text="Decline"
              />
            </.form>
          </:action>
        </.table>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event(
        "update_status",
        %{"status" => status, "record_id" => record_id},
        socket
      )
      when status in ["approved", "declined"] do
    record_id = String.to_integer(record_id)

    case Sanbase.Ecosystem.ChangeSuggestion.update_status(record_id, status) do
      {:ok, _} ->
        rows = update_assigns_row(socket.assigns.rows, record_id, status)

        socket =
          socket
          |> assign(:rows, rows)
          |> put_flash(:info, "Successfully accepted the suggested changes!")

        {:noreply, socket}

      {:error, changeset} ->
        errors = Sanbase.Utils.ErrorHandling.changeset_errors_string(changeset)

        socket =
          socket
          |> put_flash(:error, "Error accepting the suggested changes.\n Reason: #{errors}!")

        {:noreply, socket}
    end
  end

  defp update_assigns_row(rows, record_id, status) do
    rows
    |> Enum.map(fn
      %{id: ^record_id} = record ->
        record
        |> Map.put(:status, status)

      record ->
        record
    end)
    |> order_records()
  end

  defp list_all_submissions() do
    Sanbase.Ecosystem.ChangeSuggestion.list_all_submissions()
    |> Enum.map(fn struct ->
      %{
        id: struct.id,
        project_id: struct.project.id,
        project_name: struct.project.name,
        status: struct.status,
        notes: struct.notes,
        inserted_at: struct.inserted_at,
        added_ecosystems: struct.added_ecosystems,
        removed_ecosystems: struct.removed_ecosystems
      }
    end)
    |> order_records()
  end

  defp order_records(handles) do
    handles
    |> Enum.sort_by(
      fn record ->
        case record.status do
          "pending_approval" -> 1
          "approved" -> 2
          "declined" -> 3
        end
      end,
      :asc
    )
  end
end
