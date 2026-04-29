defmodule SanbaseWeb.SuggestGithubOrganizationsAdminLive do
  use SanbaseWeb, :live_view

  import SanbaseWeb.AdminLiveHelpers,
    only: [order_records_by_status: 1, update_row_by_id: 3, put_changeset_error_flash: 3]

  alias SanbaseWeb.UserFormsComponents
  alias SanbaseWeb.AdminSharedComponents

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
            <AdminSharedComponents.status_badge status={row.status} />
          </:col>
          <:col :let={row} label="Asset">
            <.link
              class="link link-primary"
              href={~p"/admin/generic/#{row.project_id}?resource=projects"}
              target="_blank"
            >
              {row.project_name}
            </.link>
          </:col>
          <:col :let={row} label="Added Github Organizations">
            <UserFormsComponents.github_organizations_group
              github_organizations={row.added_organizations}
              github_organization_colors_class="badge-success"
            />
          </:col>
          <:col :let={row} label="Removed Github Organizations">
            <UserFormsComponents.github_organizations_group
              github_organizations={row.removed_organizations}
              github_organization_colors_class="badge-error"
            />
          </:col>
          <:col :let={row} label="Notes">{row.notes}</:col>
          <:action :let={row}>
            <AdminSharedComponents.approval_buttons form={@form} row_id={row.id} status={row.status} />
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
          update_row_by_id(socket.assigns.rows, record_id, %{status: record.status})

        socket =
          socket
          |> assign(:rows, rows)
          |> put_flash(:info, "Successfully reverted the approved suggested changes!")

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply,
         put_changeset_error_flash(socket, changeset, "Error accepting the suggested changes")}
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
        rows = update_row_by_id(socket.assigns.rows, record_id, %{status: status})

        socket =
          socket
          |> assign(:rows, rows)
          |> put_flash(:info, "Successfully #{status} the suggested changes!")

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply,
         put_changeset_error_flash(socket, changeset, "Error accepting the suggested changes")}
    end
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
    |> order_records_by_status()
  end
end
