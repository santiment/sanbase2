defmodule SanbaseWeb.MetricRegistrySyncLive do
  use SanbaseWeb, :live_view

  alias SanbaseWeb.AvailableMetricsComponents
  @impl true
  def mount(_params, _session, socket) do
    metrics = Sanbase.Metric.Registry.all() |> Enum.filter(&(&1.sync_status == "not_synced"))

    {:ok,
     socket
     |> assign(
       metrics: metrics,
       sync_metric_ids: Enum.map(metrics, & &1.id) |> MapSet.new()
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col items-start justify-evenly">
      <div class="text-gray-400 text-sm py-2">
        <div>
          Showing <%= length(@metrics) %> metrics that are not synced
        </div>
      </div>
      <div class="my-4">
        <AvailableMetricsComponents.available_metrics_button
          text="Back to Metric Registry"
          href={~p"/admin2/metric_registry"}
          icon="hero-arrow-uturn-left"
        />
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
      <.table id="metrics_registry" rows={@metrics}>
        <:col :let={row} label="Should Sync">
          <.checkbox row={row} sync_metric_ids={@sync_metric_ids} />
        </:col>
        <:col :let={row} label="ID">
          <%= row.id %>
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
        text="Sync Metrics"
        phx_click="sync"
        class="bg-blue-700 hover:bg-blue-800 text-white"
        count={MapSet.size(@sync_metric_ids)}
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
      <%= @text %>
      <span :if={@count} class="text-gray-400">(<%= @count %>)</span>
    </button>
    """
  end

  @impl true
  def handle_event("sync", _params, socket) do
    Process.sleep(5000)
    {:noreply, socket}
  end

  def handle_event("update_should_sync", %{"metric_registry_id" => id} = params, socket) do
    checked = Map.get(params, "value") == "on"

    sync_metric_ids =
      if checked do
        MapSet.put(socket.assigns.sync_metric_ids, id)
      else
        MapSet.delete(socket.assigns.sync_metric_ids, id)
      end

    {:noreply, assign(socket, sync_metric_ids: sync_metric_ids)}
  end

  def handle_event("select_all", _params, socket) do
    {:noreply,
     assign(socket, sync_metric_ids: Enum.map(socket.assigns.metrics, & &1.id) |> MapSet.new())}
  end

  def handle_event("deselect_all", _params, socket) do
    {:noreply, assign(socket, sync_metric_ids: MapSet.new())}
  end

  defp metric_names(assigns) do
    ~H"""
    <div class="flex flex-col">
      <div class="text-black text-base"><%= @human_readable_name %></div>
      <div class="text-gray-900 text-sm"><%= @metric %> (API)</div>
      <div class="text-gray-900 text-sm"><%= @internal_metric %> (DB)</div>
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
        checked={@row.id in @sync_metric_ids}
        class="w-4 h-4 text-blue-600 bg-gray-100 border-gray-300 rounded"
        phx-click={JS.push("update_should_sync", value: %{metric_registry_id: @row.id})}
        }
      />
    </div>
    """
  end
end
