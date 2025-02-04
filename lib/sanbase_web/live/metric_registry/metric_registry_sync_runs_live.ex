defmodule SanbaseWeb.MetricRegistrySyncRunsLive do
  use SanbaseWeb, :live_view

  alias SanbaseWeb.AvailableMetricsComponents

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
      <h1 class="text-blue-700 text-2xl mb-4">
        Metric Registry Sync Runs
      </h1>
      <div class="text-gray-400 text-sm py-2">
        <div>
          Showing the last {length(@syncs)} syncs
        </div>
      </div>
      <div class="my-4">
        <AvailableMetricsComponents.available_metrics_button
          text="Back to Metric Registry"
          href={~p"/admin2/metric_registry"}
          icon="hero-home"
        />

        <AvailableMetricsComponents.available_metrics_button
          text="Back to Sync View"
          href={~p"/admin2/metric_registry/sync"}
          icon="hero-arrow-uturn-left"
        />
      </div>
      <.table id="metrics_registry_sync_runs" rows={@syncs}>
        <:col :let={row} label="Datetime">
          {row.inserted_at}
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
          <div class="flex flex-col">
            <span>{row.status}</span>
            <span
              :if={execution_too_long?(row.status, row.inserted_at)}
              class="text-red-500"
              data-popover-target={"popover-executing-too-long-#{row.id}"}
            >
              <.icon name="hero-exclamation-circle" /> Executing for too long!
              ({rough_duration_since(row.inserted_at)})
            </span>
          </div>
        </:col>

        <:col :let={row} label="No. Metrics Synced">
          {length(row.content)}
        </:col>

        <:col :let={row} label="Metrics Synced">
          <.list_synced_metrics content={row.content} />
        </:col>

        <:col :let={row}>
          <AvailableMetricsComponents.link_button
            text="Details"
            href={~p"/admin2/metric_registry/sync/#{row.uuid}"}
          />
          <span :if={execution_too_long?(row.status, row.inserted_at)}>
            <AvailableMetricsComponents.event_button
              phx_click="cancel_run"
              class="bg-amber-600 hover:bg-amber-800"
              phx-value-sync-uuid={row.uuid}
              display_text="Cancel Run"
            />
          </span>
        </:col>
        end
      </.table>
    </div>
    """
  end

  @impl true
  def handle_event("cancel_run", %{"sync-uuid" => sync_uuid}, socket) do
    case Sanbase.Metric.Registry.Sync.cancel_run(sync_uuid) do
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

  defp rough_duration_since(%NaiveDateTime{} = ndt) do
    seconds = NaiveDateTime.diff(NaiveDateTime.utc_now(), ndt, :second)

    cond do
      seconds < 3600 ->
        "#{div(seconds, 60)} minutes"

      seconds < 86400 ->
        "#{div(seconds, 3600)} hours"

      true ->
        days = div(seconds, 86400)
        hours = div(rem(seconds, 86400), 3600)
        "#{days} days" <> if(hours == 0, do: "", else: " #{hours} hours")
    end
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

  defp list_synced_metrics(assigns) do
    ~H"""
    <div class="max-w-xl">
      {Enum.map(@content, & &1["metric"]) |> Enum.join(", ")}
    </div>
    """
  end

  defp get_syncs() do
    Sanbase.Metric.Registry.Sync.last_syncs(20)
    |> Enum.map(fn sync -> Map.update!(sync, :content, &Jason.decode!/1) end)
  end
end
