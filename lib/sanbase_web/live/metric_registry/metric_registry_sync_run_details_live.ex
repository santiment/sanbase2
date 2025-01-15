defmodule SanbaseWeb.MetricRegistrySyncRunDetailsLive do
  use SanbaseWeb, :live_view

  @impl true
  def mount(%{"uuid" => sync_uuid}, _session, socket) do
    {:ok, sync} =
      Sanbase.Metric.Registry.Sync.by_uuid(sync_uuid)

    sync = sync |> Map.update!(:content, &Jason.decode!/1)

    {:ok,
     socket
     |> assign(
       page_title: "Metric Registry | Sync Details",
       sync: sync
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col space-y-8 ">
      <h1 class="text-blue-700 text-2xl mb-4">
        Metric Registry Sync Details | {@sync.uuid}
      </h1>
      <div :for={metric <- @sync.content}>
        {Jason.encode!(metric, pretty: true)}
      </div>
    </div>
    """
  end
end
