defmodule SanbaseWeb.SuggestGithubOrganizationsAdminLive do
  use SanbaseWeb, :live_view

  alias SanbaseWeb.UserFormsComponents
  alias SanbaseWeb.AdminFormsComponents

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
      <div class="flex-1 p:2 sm:p-6 justify-evenly">
        <.table id="github_organizations_changes_suggestions" rows={@rows}>
          <:col :let={row} label="Status">
            <AdminFormsComponents.status status={row.status} />
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
          <:col :let={row} label="Added Github Organizations">
            <UserFormsComponents.github_organizations_group
              github_organizations={row.added_organizations}
              github_organization_colors_class="bg-green-100 text-green-800"
            />
          </:col>
          <:col :let={row} label="Removed Github Organizations">
            <UserFormsComponents.github_organizations_group
              github_organizations={row.removed_organizations}
              github_organization_colors_class="bg-red-100 text-red-800"
            />
          </:col>
          <:col :let={row} label="Notes"><%= row.notes %></:col>
          <:action :let={row}>
            <.form
              for={@form}
              phx-submit="update_status"
              class="flex flex-col lg:flex-row space-y-2 lg:space-y-0 md:space-x-2"
            >
              <input type="hidden" name="record_id" value={row.id} />
              <AdminFormsComponents.button
                name="status"
                value="approved"
                class={
                  if row.status == "pending_approval",
                    do: "bg-green-600 hover:bg-green-800",
                    else: "bg-gray-300"
                }
                disabled={row.status != "pending_approval"}
                display_text="Approve"
              />
              <AdminFormsComponents.button
                name="status"
                value="declined"
                class={
                  if row.status == "pending_approval",
                    do: "bg-red-600 hover:bg-red-800",
                    else: "bg-gray-300"
                }
                disabled={row.status != "pending_approval"}
                display_text="Decline"
              />
              <AdminFormsComponents.button
                name="status"
                value="undo"
                class={
                  if row.status != "pending_approval",
                    do: "bg-yellow-400 hover:bg-yellow-800",
                    else: "bg-gray-300"
                }
                disabled={row.status == "pending_approval"}
                display_text="Undo"
              />
            </.form>
          </:action>
        </.table>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("update_status", %{"status" => "undo", "record_id" => record_id}, socket) do
    record_id = String.to_integer(record_id)

    case Sanbase.Project.GithubOrganization.ChangeSuggestion.undo_suggestion(record_id) do
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
        "update_status",
        %{"status" => status, "record_id" => record_id},
        socket
      )
      when status in ["approved", "declined"] do
    record_id = String.to_integer(record_id)

    case Sanbase.Project.GithubOrganization.ChangeSuggestion.update_status(record_id, status) do
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
      %{id: ^record_id} = record ->
        record
        |> Map.put(:status, status)

      record ->
        record
    end)
    |> order_records()
  end

  defp list_all_submissions() do
    Sanbase.Project.GithubOrganization.ChangeSuggestion.list_all_submissions()
    |> Enum.map(fn struct ->
      %{
        id: struct.id,
        project_id: struct.project.id,
        project_name: struct.project.name,
        status: struct.status,
        notes: struct.notes,
        inserted_at: struct.inserted_at,
        added_organizations: struct.added_organizations,
        removed_organizations: struct.removed_organizations
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
