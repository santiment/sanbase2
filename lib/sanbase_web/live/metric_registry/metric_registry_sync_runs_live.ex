defmodule SanbaseWeb.MetricRegistrySyncRunsLive do
  use SanbaseWeb, :live_view

  alias SanbaseWeb.AdminSharedComponents

  @pubsub_topic "sanbase_metric_registry_sync"
  @impl true
  def mount(_params, _session, socket) do
    SanbaseWeb.Endpoint.subscribe(@pubsub_topic)

    syncs = get_syncs()

    {:ok,
     socket
     |> assign(syncs: syncs, page_title: "Metric Registry | Past Sync Runs")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col items-start justify-evenly">
      <AdminSharedComponents.page_header
        title="Metric Registry Sync Runs"
        current_user={@current_user}
        current_user_role_names={@current_user_role_names}
        trim_role_prefix="Metric Registry "
      />
      <div class="text-gray-400 text-sm py-2">
        Showing the last {length(@syncs)} syncs
      </div>
      <div class="my-4">
        <AdminSharedComponents.nav_button
          text="Back to Metric Registry"
          href={~p"/admin/metric_registry"}
          icon="hero-home"
        />

        <AdminSharedComponents.nav_button
          text="Back to Sync View"
          href={~p"/admin/metric_registry/sync"}
          icon="hero-arrow-uturn-left"
        />
      </div>
      <.table id="metrics_registry_sync_runs" rows={@syncs}>
        <:col :let={row} label="Run Type">
          <.formatted_dry_run is_dry_run={row.is_dry_run} />
        </:col>
        <:col :let={row} label="Datetime">
          <div>
            <div>{Timex.format!(row.inserted_at, "%F %T%:z", :strftime)}</div>
            <div class="text-gray-500">
              ({Sanbase.Utils.DateTime.rough_duration_since(row.inserted_at)} ago)
            </div>
          </div>
        </:col>

        <:col :let={row} label="UUID">
          {row.uuid}
        </:col>

        <:col :let={row} label="Type">
          <span :if={row.sync_type == "outgoing"} class="font-bold text-blue-500">
            <.icon name="hero-phone-arrow-up-right" />
            {String.upcase(row.sync_type)}
          </span>

          <span :if={row.sync_type == "incoming"} class="font-bold text-amber-500">
            <.icon name="hero-phone-arrow-down-left" />
            {String.upcase(row.sync_type)}
          </span>
        </:col>
        <:col :let={row} label="Status">
          <.formatted_completed_status id={row.id} status={row.status} inserted_at={row.inserted_at} />
        </:col>

        <:col :let={row} label="Started By">
          {row.started_by || "Unknown"}
        </:col>
        <:col :let={row} label="No. Metrics Synced">
          {length(row.content)}
        </:col>

        <:col :let={row} label="Metrics Synced">
          <.list_synced_metrics content={row.content} />
        </:col>

        <:col :let={row}>
          <AdminSharedComponents.nav_button
            text="Details"
            href={~p"/admin/metric_registry/sync/#{row.sync_type}/#{row.uuid}"}
          />
          <span :if={execution_too_long?(row.status, row.inserted_at)}>
            <AdminSharedComponents.action_button
              phx_click="cancel_run"
              class="bg-amber-600 hover:bg-amber-800"
              text="Cancel Run"
              phx-value-sync-uuid={row.uuid}
              phx-value-sync-type={row.sync_type}
            />
          </span>
        </:col>
      </.table>
    </div>
    """
  end

  @impl true
  def handle_event("cancel_run", %{"sync-uuid" => sync_uuid, "sync-type" => sync_type}, socket) do
    case Sanbase.Metric.Registry.Sync.cancel_run(sync_uuid, sync_type) do
      {:ok, sync} ->
        sync = Map.update!(sync, :content, &Jason.decode!/1)

        syncs =
          socket.assigns.syncs
          |> Enum.map(&if &1.uuid == sync.uuid, do: sync, else: &1)

        {:noreply,
         socket
         |> put_flash(:info, "Sucessfully cancelled a long-running sync")
         |> assign(:syncs, syncs)}

      {:error, error} ->
        {:noreply,
         socket
         |> put_flash(:error, error)}
    end
  end

  @impl true
  def handle_info(%{topic: @pubsub_topic}, socket) do
    {:noreply,
     socket
     |> assign(syncs: get_syncs())
     |> put_flash(:info, "Sync data updated due to action of another.")}
  end

  defp execution_too_long?(status, inserted_at) do
    status == "executing" and
      NaiveDateTime.diff(NaiveDateTime.utc_now(), inserted_at, :second) > 60
  end

  attr :id, :any, required: true
  attr :status, :string, required: true
  attr :inserted_at, :any, required: true

  defp formatted_completed_status(assigns) do
    ~H"""
    <div class="flex flex-col">
      <span :if={@status == "completed"} class="text-green-500">
        <.icon name="hero-check-circle" /> Completed
      </span>

      <span :if={@status in ["failed", "cancelled"]} class="text-red-500">
        <.icon name="hero-x-circle" /> {String.capitalize(@status)}
      </span>

      <span :if={@status in ["executing", "scheduled"]} class="text-amber-500" }>
        <.icon name="hero-ellipsis-horizontal" /> {String.capitalize(@status)}
      </span>
      <span
        :if={execution_too_long?(@status, @inserted_at)}
        class="text-red-500"
        data-popover-target={"popover-executing-too-long-#{@id}"}
      >
        <.icon name="hero-exclamation-circle" /> Executing for too long!
        ({Sanbase.Utils.DateTime.rough_duration_since(@inserted_at)})
      </span>
    </div>
    """
  end

  defp formatted_dry_run(assigns) do
    ~H"""
    <span :if={@is_dry_run} class="text-fuchsia-300 font-bold">
      DRY RUN
    </span>
    <span :if={!@is_dry_run} class="text-green-500 font-bold">
      REAL RUN
    </span>
    """
  end

  defp list_synced_metrics(assigns) do
    ~H"""
    <div class="max-w-xl">
      {Enum.map(@content, & &1["metric"]) |> Enum.join(", ")}
    </div>
    """
  end

  defp get_syncs() do
    Sanbase.Metric.Registry.Sync.last_syncs(100)
    |> Enum.map(fn sync -> Map.update!(sync, :content, &Jason.decode!/1) end)
  end
end
