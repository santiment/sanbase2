defmodule SanbaseWeb.MetricRegistryHistoryLive do
  use SanbaseWeb, :live_view

  alias SanbaseWeb.AvailableMetricsComponents

  @impl true
  def mount(%{"id" => metric_registry_id}, _session, socket) do
    {:ok, metric_registry} = Sanbase.Metric.Registry.by_id(metric_registry_id)
    {:ok, list} = get_history_changes_list(metric_registry_id)

    {:ok,
     socket
     |> assign(
       page_title: "Metric Registry | History",
       metric_registry: metric_registry,
       history_list: list
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col space-y-8 ">
      <h1 class="text-blue-700 text-2xl mb-4">
        Metric Registry History
      </h1>
      <SanbaseWeb.MetricRegistryComponents.user_details
        current_user={@current_user}
        current_user_role_names={@current_user_role_names}
      />
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
      <div class="font-bold text-xl text-blue-800">{@metric_registry.metric}</div>
      <.table id="metrics_registry_sync_runs" rows={@history_list}>
        <:col :let={row} label="ID">
          {row.id}
        </:col>
        <:col :let={row} label="Datetime">
          {Timex.format!(row.inserted_at, "%F %T%:z", :strftime)}
        </:col>
        <:col :let={row} label="Change Trigger">
          <.change_trigger_formatted change_trigger={row.change_trigger} />
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
      list
      |> Enum.sort_by(& &1.id, :desc)
      |> Enum.map(fn %{old: old, new: new} = struct ->
        new = Jason.decode!(new)
        old = Jason.decode!(old)

        changes = ExAudit.Diff.diff(old, new)
        changes = Sanbase.ExAudit.Patch.format_patch(%{patch: changes})

        Map.from_struct(struct) |> Map.put(:changes, changes)
      end)

    {:ok, data}
  end

  defp change_trigger_formatted(assigns) do
    ~H"""
    <span
      :if={@change_trigger}
      class={[
        "px-3 py-2 text-xs font-semibold text-white rounded-full",
        get_bg_color(@change_trigger)
      ]}
    >
      {@change_trigger |> String.replace("_", " ") |> String.upcase()}
    </span>
    """
  end

  defp get_bg_color(change_trigger) do
    case change_trigger do
      "sync_apply" -> "bg-blue-800"
      "change_request_approve" -> "bg-green-800"
      "change_request_undo" -> "bg-red-800"
      _ -> "bg-gray-800"
    end
  end
end
