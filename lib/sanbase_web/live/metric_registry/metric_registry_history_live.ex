defmodule SanbaseWeb.MetricRegistryHistoryLive do
  use SanbaseWeb, :live_view

  alias SanbaseWeb.AdminSharedComponents

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
      <AdminSharedComponents.page_header
        title="Metric Registry History"
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

      <div class="divider my-8"></div>
      <div class="font-bold text-xl text-primary">{@metric_registry.metric}</div>
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
    <span :if={@change_trigger} class={["badge badge-sm text-nowrap", badge_variant(@change_trigger)]}>
      {@change_trigger |> String.replace("_", " ") |> String.upcase()}
    </span>
    """
  end

  defp badge_variant(change_trigger) do
    case change_trigger do
      "sync_apply" -> "badge-info"
      "change_request_approve" -> "badge-success"
      "change_request_undo" -> "badge-error"
      _ -> "badge-neutral"
    end
  end
end
