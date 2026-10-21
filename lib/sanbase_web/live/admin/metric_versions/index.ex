defmodule SanbaseWeb.Admin.MetricVersionsLive.Index do
  @moduledoc ~s"""
  Every metric version with who can use it. A version can be created here without
  any plan access - it is then available to nobody until plans are added on its page
  (`SanbaseWeb.Admin.MetricVersionsLive.Show`).
  """

  use SanbaseWeb, :live_view

  import SanbaseWeb.Admin.MetricVersionsLive.Components

  alias Sanbase.Admin.Permissions
  alias Sanbase.Metric.VersionAlias
  alias Sanbase.Metric.VersionPlanAccess

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Metric versions")
     |> assign(:can_edit?, Permissions.can?(:edit, roles: socket.assigns.current_user_role_names))
     |> assign(:products, VersionPlanAccess.products())
     |> assign(:show_new?, false)
     |> assign_new_form(%{})
     |> load()}
  end

  @impl true
  def handle_event("toggle_new", _params, socket) do
    {:noreply, socket |> assign(:show_new?, not socket.assigns.show_new?) |> assign_new_form(%{})}
  end

  def handle_event("validate_new", %{"version_alias" => params}, socket) do
    {:noreply, assign_new_form(socket, params, :validate)}
  end

  def handle_event("create", %{"version_alias" => params}, socket) do
    if socket.assigns.can_edit? do
      case VersionAlias.create(params) do
        {:ok, version} ->
          {:noreply,
           socket
           |> put_flash(:info, "Created #{version.version_name}. Add the plans that can use it.")
           |> push_navigate(to: ~p"/admin/metric_versions/#{version.id}")}

        {:error, changeset} ->
          {:noreply, assign(socket, :new_form, to_form(changeset, action: :insert))}
      end
    else
      {:noreply, put_flash(socket, :error, "You need the Admin Panel Editor role to do this.")}
    end
  end

  defp assign_new_form(socket, params, action \\ nil) do
    changeset = VersionAlias.changeset(%VersionAlias{}, params)
    assign(socket, :new_form, to_form(changeset, action: action))
  end

  defp load(socket), do: assign(socket, :versions, VersionAlias.list_with_plan_access())

  defp nobody_can_use?(version) do
    not default_version?(version) and not experimental?(version) and version.plan_access == []
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-7xl space-y-6">
      <div class="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1 class="text-3xl font-bold">Metric versions</h1>
          <p class="text-sm text-base-content/70 mt-1 max-w-3xl">
            The versions API clients can request with <code>getMetric(version: ...)</code>
            and the plans that can use each one. Version 1.0 is available to every plan.
            Any other version is available only to the plans set on its page.
            Changes apply immediately.
          </p>
        </div>
        <button
          :if={@can_edit?}
          id="new-version-button"
          type="button"
          phx-click="toggle_new"
          class="btn btn-primary btn-sm"
        >
          {if @show_new?, do: "Cancel", else: "New version"}
        </button>
      </div>

      <div :if={@show_new?} id="new-version" class="card bg-base-100 border border-base-300">
        <div class="card-body">
          <h2 class="card-title text-lg">New version</h2>
          <p class="text-sm text-base-content/70">
            The version is created with no plan access, so nobody can use it yet. Add the
            plans on its page once it is ready to be sold.
          </p>
          <.form
            for={@new_form}
            id="new-version-form"
            phx-change="validate_new"
            phx-submit="create"
            class="grid md:grid-cols-2 gap-x-6"
          >
            <.input
              field={@new_form[:scope]}
              type="select"
              label="Scope"
              options={VersionAlias.scopes()}
            />
            <.input
              field={@new_form[:exposed_in]}
              type="select"
              label="Exposed in"
              options={exposure_options()}
            />
            <.input
              field={@new_form[:version_num]}
              type="text"
              label="Version number"
              placeholder="2.2"
            />
            <.input
              field={@new_form[:version_name]}
              type="text"
              label="Version name"
              placeholder="modern_pit:v2"
            />
            <.input
              field={@new_form[:description]}
              type="textarea"
              label="Description"
              outer_div_class="md:col-span-2"
            />
            <div class="md:col-span-2 flex justify-end">
              <button
                id="create-version"
                type="submit"
                class="btn btn-primary btn-sm"
                phx-disable-with="Creating..."
              >
                Create version
              </button>
            </div>
          </.form>
        </div>
      </div>

      <div class="rounded-box border border-base-300 overflow-x-auto">
        <table id="metric-versions" class="table">
          <thead>
            <tr>
              <th>Version</th>
              <th>Scope</th>
              <th>Exposed in</th>
              <th :for={product <- @products}>{product_label(product)} plans</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <tr
              :for={version <- @versions}
              id={"metric-version-#{version.id}"}
              class="hover:bg-base-200/50"
            >
              <td>
                <div class="font-medium">{version.version_name}</div>
                <div class="font-mono text-xs text-base-content/60">{version.version_num}</div>
                <span
                  :if={nobody_can_use?(version)}
                  class="badge badge-warning badge-xs mt-1"
                  title="No plan can use this version yet."
                >
                  Needs plan access
                </span>
              </td>
              <td><.scope_badge scope={version.scope} /></td>
              <td class="text-sm">{exposure_label(version.exposed_in)}</td>
              <td :for={product <- @products}>
                <.access_summary version={version} product={product} />
              </td>
              <td class="text-right">
                <.link
                  id={"configure-version-#{version.id}"}
                  navigate={~p"/admin/metric_versions/#{version.id}"}
                  class="btn btn-ghost btn-sm"
                >
                  {if @can_edit?, do: "Configure", else: "View"}
                </.link>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end
end
