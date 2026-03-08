defmodule SanbaseWeb.MetricRegistrySyncRunDetailsLive do
  use SanbaseWeb, :live_view

  alias SanbaseWeb.AdminSharedComponents
  alias Sanbase.Metric.Registry.Sync
  @impl true
  def mount(%{"uuid" => sync_uuid, "sync_type" => sync_type}, _session, socket) do
    {:ok, sync} =
      Sanbase.Metric.Registry.Sync.by_uuid(sync_uuid, sync_type)

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
      <AdminSharedComponents.page_header
        title={"Metric Registry Sync Details | #{@sync.uuid}"}
        current_user={@current_user}
        current_user_role_names={@current_user_role_names}
        trim_role_prefix="Metric Registry "
      />
      <div class="my-4">
        <AdminSharedComponents.nav_button
          text="Back to Metric Registry"
          href={~p"/admin/metric_registry"}
          icon="hero-home"
        />

        <AdminSharedComponents.nav_button
          text="List Sync Runs"
          href={~p"/admin/metric_registry/sync_runs"}
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
