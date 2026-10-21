defmodule SanbaseWeb.Admin.MetricVersionsLive.Show do
  @moduledoc ~s"""
  One metric version: its details, and a grid per product of the plans that can use
  it. The grid is edited locally and saved in one go, replacing the version's plan
  access (`Sanbase.Metric.VersionPlanAccess.replace_all/2`).
  """

  use SanbaseWeb, :live_view

  import SanbaseWeb.Admin.MetricVersionsLive.Components

  alias Sanbase.Admin.Permissions
  alias Sanbase.Metric.VersionAlias
  alias Sanbase.Metric.VersionPlanAccess

  @no_access %{enabled: false, billing_interval: "any", accessible_if_trial: true}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     socket
     |> assign(:can_edit?, Permissions.can?(:edit, roles: socket.assigns.current_user_role_names))
     |> assign(:products, VersionPlanAccess.products())
     |> load(id)}
  end

  @impl true
  def handle_event("validate_details", %{"version_alias" => params}, socket) do
    {:noreply, assign_details_form(socket, params, :validate)}
  end

  def handle_event("save_details", %{"version_alias" => params}, socket) do
    with_edit_permission(socket, fn ->
      case VersionAlias.update(socket.assigns.version, params) do
        {:ok, version} ->
          {:noreply, socket |> put_flash(:info, "Saved.") |> load(version.id)}

        {:error, changeset} ->
          {:noreply, assign(socket, :details_form, to_form(changeset, action: :update))}
      end
    end)
  end

  def handle_event("delete", _params, socket) do
    with_edit_permission(socket, fn ->
      {:ok, version} = VersionAlias.delete(socket.assigns.version)

      {:noreply,
       socket
       |> put_flash(:info, "Deleted #{version.version_name}.")
       |> push_navigate(to: ~p"/admin/metric_versions")}
    end)
  end

  def handle_event("change_access", %{"access" => params}, socket) do
    {:noreply, assign(socket, :access, merge_access(socket.assigns.access, params))}
  end

  def handle_event("change_access", _params, socket), do: {:noreply, socket}

  def handle_event("discard_access", _params, socket) do
    {:noreply, assign(socket, :access, socket.assigns.saved_access)}
  end

  def handle_event("save_access", _params, socket) do
    with_edit_permission(socket, fn ->
      %{version: version, access: access} = socket.assigns

      case VersionPlanAccess.replace_all(version, enabled_entries(access, version)) do
        {:ok, _rows} ->
          {:noreply,
           socket
           |> put_flash(:info, "Plan access saved. It applies to requests right away.")
           |> load(version.id)}

        {:error, changeset} ->
          {:noreply, put_flash(socket, :error, "Not saved: #{errors_to_string(changeset)}")}
      end
    end)
  end

  defp with_edit_permission(socket, fun) do
    if socket.assigns.can_edit? do
      fun.()
    else
      {:noreply, put_flash(socket, :error, "You need the Admin Panel Editor role to do this.")}
    end
  end

  defp load(socket, id) do
    version = VersionAlias.get_with_plan_access!(id)
    access = access_from_rows(version.plan_access)

    socket
    |> assign(:page_title, "Metric version #{version.version_name}")
    |> assign(:version, version)
    |> assign(:access, access)
    |> assign(:saved_access, access)
    |> assign(:grid_editable?, socket.assigns.can_edit? and access_configurable?(version))
    |> assign_details_form(%{})
  end

  defp assign_details_form(socket, params, action \\ nil) do
    %{version: version} = socket.assigns
    changeset = VersionAlias.changeset(version, params)
    exposed_in = Ecto.Changeset.get_field(changeset, :exposed_in)

    socket
    |> assign(:details_form, to_form(changeset, action: action))
    |> assign(:removed_by_exposure, removed_by_exposure(version, exposed_in))
  end

  # The saved plan access rows that saving the new `exposed_in` would delete.
  defp removed_by_exposure(%VersionAlias{} = version, exposed_in) do
    narrowed = %VersionAlias{version | exposed_in: exposed_in}
    Enum.reject(version.plan_access, &VersionAlias.exposed_in?(narrowed, &1.product))
  end

  # The default version is always available and Experimental ones follow the alpha
  # rule, so plan access is not used for them.
  defp access_configurable?(version),
    do: not default_version?(version) and not experimental?(version)

  # %{{product, plan} => %{enabled:, billing_interval:, accessible_if_trial:}} for every
  # plan of the grid. Several rows of one plan (one per interval) show as one entry.
  defp access_from_rows(rows) do
    empty =
      for product <- VersionPlanAccess.products(),
          plan <- [VersionPlanAccess.any_plan() | VersionPlanAccess.plans(product)],
          into: %{},
          do: {{product, plan}, @no_access}

    Enum.reduce(rows, empty, fn row, access ->
      Map.update(access, {row.product, row.plan}, entry_from_row(row), fn existing ->
        if existing.enabled and existing.billing_interval != row.billing_interval,
          do: %{existing | billing_interval: "any"},
          else: entry_from_row(row)
      end)
    end)
  end

  defp entry_from_row(row) do
    %{
      enabled: true,
      billing_interval: row.billing_interval,
      accessible_if_trial: row.accessible_if_trial
    }
  end

  # Disabled inputs are not submitted, so a value that is missing keeps what it was.
  defp merge_access(access, params) do
    Enum.reduce(params, access, fn {product, plans}, access ->
      Enum.reduce(plans, access, fn {plan, values}, access ->
        Map.update(access, {product, plan}, @no_access, fn entry ->
          %{
            enabled: boolean(values["enabled"], entry.enabled),
            billing_interval: values["billing_interval"] || entry.billing_interval,
            accessible_if_trial: boolean(values["accessible_if_trial"], entry.accessible_if_trial)
          }
        end)
      end)
    end)
  end

  defp boolean(nil, default), do: default
  defp boolean(value, _default), do: value == "true"

  defp enabled_entries(access, version) do
    for {{product, plan}, %{enabled: true} = entry} <- access,
        VersionAlias.exposed_in?(version, product) do
      %{
        product: product,
        plan: plan,
        billing_interval: entry.billing_interval,
        accessible_if_trial: entry.accessible_if_trial
      }
    end
  end

  # [{plan, entry}] in grid order. Plans set outside this page (a Sanbase row for a
  # SanAPI plan) are shown too, so saving does not drop them.
  defp grid_rows(access, product) do
    known = [VersionPlanAccess.any_plan() | VersionPlanAccess.plans(product)]
    other = for {{^product, plan}, _} <- access, plan not in known, do: plan

    for plan <- known ++ Enum.sort(other), do: {plan, entry(access, product, plan)}
  end

  defp entry(access, product, plan), do: Map.get(access, {product, plan}, @no_access)

  # "All plans" without billing or trial limits already gives every other plan access.
  defp covered_by_any?(access, product) do
    match?(
      %{enabled: true, billing_interval: "any", accessible_if_trial: true},
      entry(access, product, VersionPlanAccess.any_plan())
    )
  end

  defp summary(access, product) do
    entries =
      for {{^product, plan}, %{enabled: true} = entry} <- access do
        Map.merge(entry, %{product: product, plan: plan})
      end

    case entries do
      [] -> "Nobody"
      entries -> entries |> sort_entries() |> Enum.map_join(", ", &access_label/1)
    end
  end

  defp field_name(product, plan, field), do: "access[#{product}][#{plan}][#{field}]"
  defp field_id(product, plan, field), do: "access-#{product}-#{plan}-#{field}"

  defp errors_to_string(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, _opts} -> msg end)
    |> Enum.map_join("; ", fn {field, messages} -> "#{field} #{Enum.join(messages, ", ")}" end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-7xl space-y-6">
      <div>
        <.link navigate={~p"/admin/metric_versions"} class="link link-hover text-sm">
          ← Metric versions
        </.link>
        <div class="mt-2 flex flex-wrap items-start justify-between gap-4">
          <div>
            <h1 class="text-3xl font-bold">{@version.version_name}</h1>
            <div class="mt-1 flex items-center gap-2 text-sm text-base-content/70">
              <span class="font-mono">{@version.version_num}</span>
              <.scope_badge scope={@version.scope} />
            </div>
          </div>
          <button
            :if={@can_edit?}
            id="delete-version"
            type="button"
            phx-click="delete"
            data-confirm={"Delete #{@version.version_name}? API clients that send this name will get an error, and its plan access is deleted with it."}
            class="btn btn-error btn-outline btn-sm"
          >
            Delete version
          </button>
        </div>
      </div>

      <div class="card bg-base-100 border border-base-300">
        <div class="card-body">
          <h2 class="card-title text-lg">Details</h2>
          <.form
            for={@details_form}
            id="version-details-form"
            phx-change="validate_details"
            phx-submit="save_details"
            class="grid md:grid-cols-2 gap-x-6"
          >
            <.input
              field={@details_form[:version_name]}
              type="text"
              label="Version name"
              disabled={not @can_edit?}
            />
            <div>
              <.input
                field={@details_form[:exposed_in]}
                type="select"
                label="Exposed in"
                options={exposure_options()}
                disabled={not @can_edit?}
              />
              <p
                :if={@removed_by_exposure != []}
                id="exposure-removes-access"
                class="text-sm text-warning -mt-1 mb-2"
              >
                Saving removes the access of {Enum.map_join(
                  @removed_by_exposure,
                  ", ",
                  &"#{product_label(&1.product)} #{access_label(&1)}"
                )}.
              </p>
            </div>
            <.input
              field={@details_form[:description]}
              type="textarea"
              label="Description"
              outer_div_class="md:col-span-2"
              disabled={not @can_edit?}
            />
            <div :if={@can_edit?} class="md:col-span-2 flex justify-end">
              <button
                id="save-details"
                type="submit"
                class="btn btn-primary btn-sm"
                phx-disable-with="Saving..."
              >
                Save details
              </button>
            </div>
          </.form>
        </div>
      </div>

      <div class="card bg-base-100 border border-base-300">
        <div class="card-body">
          <div class="flex flex-wrap items-center justify-between gap-2">
            <h2 class="card-title text-lg">Plan access</h2>
            <span :if={@access != @saved_access} id="unsaved-access" class="badge badge-warning">
              Unsaved changes
            </span>
          </div>

          <div :if={default_version?(@version)} class="alert alert-info text-sm">
            Version {@version.version_num} is the default version. Every plan can always use it.
          </div>
          <div :if={experimental?(@version)} class="alert alert-info text-sm">
            Experimental versions are available only to users with alpha access.
            Plan access is not used for them.
          </div>

          <p :if={access_configurable?(@version)} class="text-sm text-base-content/70">
            Tick the plans that can use this version. A plan that is not ticked cannot use it.
            Custom plans count as the plan they are based on, and bundles count as Pro.
          </p>

          <.form
            for={%{}}
            as={:access}
            id="plan-access-form"
            phx-change="change_access"
            phx-submit="save_access"
          >
            <div class="grid xl:grid-cols-2 gap-6">
              <section
                :for={product <- @products}
                id={"access-#{product}"}
                class="rounded-box border border-base-300 p-4"
              >
                <h3 class="font-semibold">
                  {product_label(product)}
                  <span class="text-xs font-normal text-base-content/60">
                    ({product_description(product)})
                  </span>
                </h3>

                <%= if VersionAlias.exposed_in?(@version, product) do %>
                  <p
                    :if={access_configurable?(@version)}
                    id={"access-summary-#{product}"}
                    class="text-sm mt-1"
                  >
                    <span class="text-base-content/60">Who can use it:</span>
                    {summary(@access, product)}
                  </p>
                  <table class="table table-sm mt-2">
                    <thead>
                      <tr>
                        <th>Plan</th>
                        <th class="text-center">Has access</th>
                        <th>Billing</th>
                        <th class="text-center">Trial users too</th>
                      </tr>
                    </thead>
                    <tbody>
                      <tr
                        :for={{plan, entry} <- grid_rows(@access, product)}
                        id={"access-#{product}-#{plan}"}
                        class={[
                          plan != "ANY" && covered_by_any?(@access, product) && "opacity-50"
                        ]}
                      >
                        <td>
                          <div class="font-medium">{plan_label(plan)}</div>
                          <div :if={plan == "ANY"} class="text-xs text-base-content/60">
                            Every plan, free users included
                          </div>
                        </td>
                        <td class="text-center">
                          <input
                            type="hidden"
                            name={field_name(product, plan, "enabled")}
                            value="false"
                            disabled={not @grid_editable?}
                          />
                          <input
                            id={field_id(product, plan, "enabled")}
                            type="checkbox"
                            name={field_name(product, plan, "enabled")}
                            value="true"
                            checked={entry.enabled}
                            disabled={not @grid_editable?}
                            class="toggle toggle-sm toggle-success"
                          />
                        </td>
                        <td>
                          <select
                            id={field_id(product, plan, "billing_interval")}
                            name={field_name(product, plan, "billing_interval")}
                            disabled={not @grid_editable? or not entry.enabled}
                            class="select select-sm select-bordered"
                          >
                            {Phoenix.HTML.Form.options_for_select(
                              interval_options(),
                              entry.billing_interval
                            )}
                          </select>
                        </td>
                        <td class="text-center">
                          <input
                            type="hidden"
                            name={field_name(product, plan, "accessible_if_trial")}
                            value="false"
                            disabled={not @grid_editable? or not entry.enabled}
                          />
                          <input
                            id={field_id(product, plan, "accessible_if_trial")}
                            type="checkbox"
                            name={field_name(product, plan, "accessible_if_trial")}
                            value="true"
                            checked={entry.accessible_if_trial}
                            disabled={not @grid_editable? or not entry.enabled}
                            class="checkbox checkbox-sm"
                          />
                        </td>
                      </tr>
                    </tbody>
                  </table>
                <% else %>
                  <p class="text-sm text-base-content/60 mt-2">
                    Not exposed in {product_label(product)}. Change "Exposed in" above to
                    configure its plans.
                  </p>
                <% end %>
              </section>
            </div>

            <div :if={@grid_editable?} class="mt-4 flex justify-end gap-2">
              <button
                id="discard-access"
                type="button"
                phx-click="discard_access"
                class="btn btn-ghost btn-sm"
                disabled={@access == @saved_access}
              >
                Discard changes
              </button>
              <button
                id="save-access"
                type="submit"
                class="btn btn-primary btn-sm"
                phx-disable-with="Saving..."
                disabled={@access == @saved_access}
              >
                Save plan access
              </button>
            </div>
          </.form>
        </div>
      </div>
    </div>
    """
  end
end
