defmodule SanbaseWeb.MetricRegistryHistoryLive do
  @moduledoc false
  use SanbaseWeb, :live_view

  alias SanbaseWeb.AvailableMetricsComponents

  @impl true
  def mount(%{"id" => metric_registry_id}, _session, socket) do
    {:ok, list} = get_history_changes_list(metric_registry_id)

    {:ok, assign(socket, page_title: "Metric Registry | History", history_list: list)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col space-y-8 ">
      <h1 class="text-blue-700 text-2xl mb-4">
        Metric Registry History
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

      <hr class="h-px my-8 bg-gray-200 border-0 dark:bg-gray-700" />
      <.table id="metrics_registry_sync_runs" rows={@history_list}>
        <:col :let={row} label="Datetime">
          {row.inserted_at}
        </:col>
        <:col :let={row} label="Changes">
          {row.changes}
        </:col>
      </.table>
    </div>
    """
  end

  defp get_history_changes_list(metric_registry_id) do
    {:ok, list} = Sanbase.Metric.Registry.Changelog.by_metric_registry_id(metric_registry_id)

    data =
      Enum.map(list, fn %{old: old, new: new} = struct ->
        new = Jason.decode!(new)
        old = Jason.decode!(old)

        changes = ExAudit.Diff.diff(old, new)
        changes = Sanbase.ExAudit.Patch.format_patch(%{patch: changes})

        struct |> Map.from_struct() |> Map.put(:changes, changes)
      end)

    {:ok, data}
  end
end
