defmodule SanbaseWeb.MetricRegistryDiffLive do
  use SanbaseWeb, :live_view

  alias SanbaseWeb.AvailableMetricsComponents
  alias Sanbase.Metric.Registry
  @impl true
  def mount(%{"id" => metric_registry_id}, _session, socket) do
    {:ok, %{id: id, last_sync_datetime: last_sync_datetime} = metric_registry} =
      Registry.by_id(metric_registry_id)

    socket =
      case metric_registry.sync_status do
        "synced" ->
          socket |> assign(html_safe_changes: nil, has_changes: false)

        "not_synced" ->
          case Registry.Changelog.state_before_last_sync(id, last_sync_datetime) do
            {:ok, old_state_json} ->
              metric_registry_map = Jason.encode!(metric_registry) |> Jason.decode!()

              diff_changes =
                ExAudit.Diff.diff(old_state_json, metric_registry_map)
                |> dbg()

              html_safe_changes = Sanbase.ExAudit.Patch.format_patch(%{patch: diff_changes})

              socket
              |> assign(
                html_safe_changes: html_safe_changes,
                has_changes: diff_changes != :not_changed
              )

            {:error, _} ->
              # If a new metric has been just created it is in `not synced` state
              # but there are no changes being made so far.
              # Note: Maybe improve visualization here?
              socket |> assign(html_safe_changes: nil, has_changes: false, has_syncs: false)
          end
      end

    {:ok,
     socket
     |> assign(
       page_title: "Metric Registry | Diff",
       metric_registry: metric_registry
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col ">
      <h1 class="text-blue-700 text-2xl mb-4">
        Metric Registry Diff Since Last Sync | {@metric_registry.metric}
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
          text="Back to Metric Page"
          href={~p"/admin2/metric_registry/show/#{@metric_registry.id}"}
          icon="hero-list-bullet"
        />
      </div>

      <.formatted_differences
        metric_registry={@metric_registry}
        has_changes={@has_changes}
        html_safe_changes={@html_safe_changes}
      />
    </div>
    """
  end

  defp formatted_differences(assigns) do
    ~H"""
    <div>
      <span class="text-amber-800 font-bold text-xl">Diff Since Last Sync</span>
      <hr class="h-px my-2 bg-gray-200 border-0 dark:bg-gray-700" />
      <!-- In synced status. -->
      <div :if={@metric_registry.sync_status == "synced"}>
        <span class="text-blue-900 font-bold text-xl">
          The metric is in Synced state!
        </span>
      </div>
      
    <!-- Not synced with changes -->
      <div :if={@metric_registry.sync_status == "not_synced" and @has_changes}>
        {@html_safe_changes}
      </div>
      
    <!-- Not synced, but without changes-->
      <div :if={@metric_registry.sync_status == "not_synced" and !@has_changes}>
        <span class="text-blue-900 font-bold text-xl">
          No changes!
        </span>
        <div class="max-w-2xl text-gray-800">
          The metric is in not synced state, but there are no changes.
          Maybe the chain of change requests approved and undone have put the metric
          in a state that is the same as the last sync.
        </div>
      </div>

      <div :if={@metric_registry.sync_status == "synced" and @has_changes}>
        <span class="text-blue-900 font-bold text-xl">
          You should never see this! If seen, report to backend team!
        </span>
      </div>
    </div>
    """
  end
end
