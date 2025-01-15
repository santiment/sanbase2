defmodule SanbaseWeb.MetricRegistrySyncRunDetailsLive do
  use SanbaseWeb, :live_view

  @impl true
  def mount(%{"uuid" => sync_uuid}, _session, socket) do
    {:ok, sync} =
      Sanbase.Metric.Registry.Sync.by_uuid(sync_uuid)

    sync = sync |> Map.update!(:content, &Jason.decode!/1)

    {:ok,
     socket
     |> assign(sync: sync)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col space-y-8 ">
      <div :for={metric <- @sync.content}>
        {Jason.encode!(metric, pretty: true)}
      </div>
    </div>
    """
  end
end
