defmodule SanbaseWeb.MetricRegistrySyncRunDetailsLive do
  @moduledoc false
  use SanbaseWeb, :live_view

  alias Sanbase.Metric.Registry.Sync
  alias SanbaseWeb.AvailableMetricsComponents

  @impl true
  def mount(%{"uuid" => sync_uuid}, _session, socket) do
    {:ok, sync} =
      Sanbase.Metric.Registry.Sync.by_uuid(sync_uuid)

    sync = Map.update!(sync, :content, &Jason.decode!/1)

    {:ok, assign(socket, page_title: "Metric Registry | Sync Details", sync: sync)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col space-y-8 ">
      <h1 class="text-blue-700 text-2xl mb-4">
        Metric Registry Sync Details | {@sync.uuid}
      </h1>

      <div class="my-4">
        <AvailableMetricsComponents.available_metrics_button
          text="Back to Metric Registry"
          href={~p"/admin2/metric_registry"}
          icon="hero-home"
        />

        <AvailableMetricsComponents.available_metrics_button
          text="List Sync Runs"
          href={~p"/admin2/metric_registry/sync_runs"}
          icon="hero-list-bullet"
        />
      </div>
      <h2>Actual Changes Applied</h2>
      <div>
        {Sync.actual_changes_formatted(@sync)}
      </div>
      <h2>Content</h2>
      <div :for={metric <- @sync.content}>
        <pre class="bg-gray-100 p-4 rounded-lg overflow-x-auto">{Jason.encode!(metric, pretty: true)}</pre>
      </div>
    </div>
    """
  end
end
