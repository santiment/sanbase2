defmodule SanbaseWeb.MetricRegistrySyncLive do
  use SanbaseWeb, :live_view

  import Sanbase.Utils.ErrorHandling, only: [changeset_errors_string: 1]

  alias SanbaseWeb.AvailableMetricsComponents
  alias Sanbase.Metric.Registry.Permissions

  @pubsub_topic "sanbase_metric_registry_sync"

  @impl true
  def mount(_params, _session, socket) do
    {syncable_metrics, not_syncable_metrics} = get_syncs_data()

    SanbaseWeb.Endpoint.subscribe(@pubsub_topic)

    {:ok,
     socket
     |> assign(
       syncable_metrics: syncable_metrics,
       is_dry_run: true,
       non_syncable_metrics: not_syncable_metrics,
       metric_ids_to_sync: Enum.map(syncable_metrics, & &1.id) |> MapSet.new(),
       page_title: "Metric Registry | Sync"
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col items-start justify-evenly">
      <h1 class="text-blue-700 text-2xl mb-4">
        Metric Registry Sync
      </h1>
      <SanbaseWeb.MetricRegistryComponents.user_details
        current_user={@current_user}
        current_user_role_names={@current_user_role_names}
      />
      <div class="text-gray-400 text-sm py-2">
        <div>
          {length(@syncable_metrics)} metric(s) available to be synced from stage to prod}
        </div>
        <div :if={@non_syncable_metrics != []}>
          {length(@non_syncable_metrics)} metric(s) not synced but need(s) to be verified first}
        </div>
      </div>
      <div class="my-4">
        <AvailableMetricsComponents.available_metrics_button
          text="Back to Metric Registry"
          href={~p"/admin/metric_registry"}
          icon="hero-home"
        />

        <AvailableMetricsComponents.available_metrics_button
          text="List Sync Runs"
          href={~p"/admin/metric_registry/sync_runs"}
          icon="hero-list-bullet"
        />
      </div>

      <div class="flex items-center mb-4 ">
        <label for="unverified-only" class="cursor-pointer ms-2 text-sm font-medium text-gray-900">
          <input
            id="is-dry-run"
            name="is_dry_run"
            checked={@is_dry_run}
            type="checkbox"
            class="w-4 h-4 text-blue-600 bg-gray-100 border-gray-300 rounded "
            phx-click="update_is_dry_sync"
          /> Dry Run
        </label>
      </div>

      <div class="flex flex-col space-y-2 md:flex-row md:space-x-2 md:space-y-0">
        <.phx_click_button
          text="Select All"
          phx_click="select_all"
          class="bg-white hover:bg-gray-100 text-zync-900"
        />
        <.phx_click_button
          text="Deselect All"
          phx_click="deselect_all"
          class="bg-white hover:bg-gray-100 text-zync-900"
        />
      </div>
      <.table id="metrics_registry" rows={@syncable_metrics}>
        <:col :let={row} label="Should Sync">
          <.checkbox row={row} metric_ids_to_sync={@metric_ids_to_sync} />
        </:col>
        <:col :let={row} label="ID">
          {row.id}
        </:col>
        <:col :let={row} label="Metric Names" col_class="max-w-[720px] break-all">
          <.metric_names
            metric={row.metric}
            internal_metric={row.internal_metric}
            human_readable_name={row.human_readable_name}
          />
        </:col>
      </.table>
      <.phx_click_button
        :if={Permissions.can?(:start_sync, roles: @current_user_role_names)}
        text="Sync Metrics"
        phx_click="sync"
        class="min-w-42 bg-blue-700 hover:bg-blue-800 text-white"
        count={MapSet.size(@metric_ids_to_sync)}
        phx_disable_with="Syncing..."
      />
    </div>
    """
  end

  attr :phx_click, :string, required: true
  attr :text, :string, required: true
  attr :count, :integer, required: false, default: nil
  attr :class, :string, required: true
  attr :phx_disable_with, :string, required: false, default: nil

  defp phx_click_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click={@phx_click}
      class={[
        "border border-gray-200 font-medium rounded-lg text-sm px-5 py-2.5 text-center inline-flex items-center gap-x-2",
        @class
      ]}
      phx-disable-with={@phx_disable_with}
    >
      {@text}
      <span :if={@count} class="text-gray-400">({@count})</span>
    </button>
    """
  end

  @impl true
  def handle_event("sync", _params, socket) do
    Permissions.raise_if_cannot(:start_sync, roles: socket.assigns.current_user_role_names)

    ids = socket.assigns.metric_ids_to_sync |> Enum.to_list()

    sync_opts = [
      dry_run: socket.assigns.is_dry_run,
      started_by: socket.assigns.current_user.email
    ]

    case Sanbase.Metric.Registry.Sync.sync(ids, sync_opts) do
      {:ok, _data} ->
        # Add some artificial wait period so there's some time for the sync
        # to finish.
        {syncable_metrics, not_syncable_metrics} = get_syncs_data()

        {:noreply,
         socket
         |> put_flash(:info, "Sucessfully initiated sync of #{length(ids)} metrics")
         |> push_navigate(to: ~p"/admin/metric_registry/sync_runs")
         |> assign(
           syncable_metrics: syncable_metrics,
           non_syncable_metrics: not_syncable_metrics,
           metric_ids_to_sync: Enum.map(syncable_metrics, & &1.id) |> MapSet.new()
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Error syncing metrics: #{changeset_errors_string(changeset)}")}
    end
  end

  def handle_event("update_is_dry_sync", params, socket) do
    {:noreply, assign(socket, is_dry_run: Map.get(params, "value") == "on")}
  end

  def handle_event("update_should_sync", %{"metric_registry_id" => id} = params, socket) do
    checked = Map.get(params, "value") == "on"

    metric_ids_to_sync =
      if checked do
        MapSet.put(socket.assigns.metric_ids_to_sync, id)
      else
        MapSet.delete(socket.assigns.metric_ids_to_sync, id)
      end

    {:noreply, assign(socket, metric_ids_to_sync: metric_ids_to_sync)}
  end

  def handle_event("select_all", _params, socket) do
    {:noreply,
     assign(socket,
       metric_ids_to_sync: Enum.map(socket.assigns.syncable_metrics, & &1.id) |> MapSet.new()
     )}
  end

  def handle_event("deselect_all", _params, socket) do
    {:noreply, assign(socket, metric_ids_to_sync: MapSet.new())}
  end

  @impl true
  def handle_info(%{topic: @pubsub_topic}, socket) do
    {syncable_metrics, not_syncable_metrics} = get_syncs_data()

    {:noreply,
     socket
     |> assign(
       syncable_metrics: syncable_metrics,
       non_syncable_metrics: not_syncable_metrics,
       metric_ids_to_sync: Enum.map(syncable_metrics, & &1.id) |> MapSet.new()
     )
     |> put_flash(:info, "Sync data updated due to action of another.")}
  end

  defp get_syncs_data() do
    metrics = Sanbase.Metric.Registry.all()

    syncable_metrics =
      metrics
      |> Enum.filter(&(&1.sync_status == "not_synced" and &1.is_verified == true))

    not_syncable_metrics =
      metrics
      |> Enum.filter(&(&1.sync_status == "not_synced" and &1.is_verified == false))

    {syncable_metrics, not_syncable_metrics}
  end

  defp metric_names(assigns) do
    ~H"""
    <div class="flex flex-col">
      <div class="text-black text-base">{@human_readable_name}</div>
      <div class="text-gray-900 text-sm">{@metric} (API)</div>
      <div class="text-gray-900 text-sm">{@internal_metric} (DB)</div>
    </div>
    """
  end

  defp checkbox(assigns) do
    ~H"""
    <div class="flex items-center mb-4 ">
      <input
        id="not-verified-only"
        name={"sync-status-#{@row.id}"}
        type="checkbox"
        checked={@row.id in @metric_ids_to_sync}
        class="w-4 h-4 text-blue-600 bg-gray-100 border-gray-300 rounded"
        phx-click={JS.push("update_should_sync", value: %{metric_registry_id: @row.id})}
        }
      />
    </div>
    """
  end
end
