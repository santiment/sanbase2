defmodule SanbaseWeb.MetricRegistrySyncDriftLive do
  use SanbaseWeb, :live_view

  alias SanbaseWeb.AdminSharedComponents
  alias Sanbase.Metric.Registry.Drift
  alias Sanbase.Metric.Registry.Permissions

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Metric Registry | Sync Drift",
       result: nil,
       error: nil,
       running?: false
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col">
      <AdminSharedComponents.page_header
        title="Metric Registry Sync Drift"
        current_user={@current_user}
        current_user_role_names={@current_user_role_names}
        trim_role_prefix="Metric Registry "
      />
      <div class="text-base-content/50 text-sm py-2 max-w-3xl">
        Compare the full local (stage) metric registry against the prod one and report
        the differences. This detects drift that the sync itself cannot see: manual DB
        interventions, deletions (which are never synced) and renames (which leave an
        orphaned record with the old name on prod). Records are matched by
        (metric, data_type, fixed_parameters) and only synced fields are compared.
      </div>
      <div class="my-4">
        <AdminSharedComponents.nav_button
          text="Back to Metric Registry"
          href={~p"/admin/metric_registry"}
          icon="hero-home"
        />

        <AdminSharedComponents.nav_button
          text="Sync Metrics"
          href={~p"/admin/metric_registry/sync"}
          icon="hero-arrows-right-left"
        />

        <AdminSharedComponents.nav_button
          text="List Sync Runs"
          href={~p"/admin/metric_registry/sync_runs"}
          icon="hero-list-bullet"
        />
      </div>

      <AdminSharedComponents.action_button
        :if={Permissions.can?(:run_sync_drift_check, roles: @current_user_role_names)}
        text={if @running?, do: "Running...", else: "Run Drift Check"}
        phx_click="run_drift_check"
        class="min-w-42 btn-primary"
        phx_disable_with="Running..."
      />

      <div :if={@error} class="my-4 text-error font-bold">
        {@error}
      </div>

      <.drift_result :if={@result} result={@result} />
    </div>
    """
  end

  defp drift_result(assigns) do
    ~H"""
    <div class="flex flex-col my-4 space-y-8">
      <div class="text-sm text-base-content/70">
        Checked at {@result.checked_at}. Local records: {@result.local_count},
        prod records: {@result.remote_count}, identical: {@result.identical_count}.
      </div>

      <div :if={no_drift?(@result)} class="text-primary font-bold text-xl">
        No drift detected. Stage and prod registries are in sync.
      </div>

      <div :if={@result.extra_on_prod != []}>
        <span class="text-error font-bold text-xl">
          Records existing only on PROD ({length(@result.extra_on_prod)})
        </span>
        <div class="text-sm text-base-content/50 max-w-3xl">
          The sync never deletes records, so these are either orphans left after a
          rename/deletion on stage, or records manually created on prod. They can
          only be cleaned up manually.
        </div>
        <.table id="extra_on_prod" rows={@result.extra_on_prod}>
          <:col :let={row} label="Metric">{row.key.metric}</:col>
          <:col :let={row} label="Data Type">{row.key.data_type}</:col>
          <:col :let={row} label="Fixed Parameters">{inspect(row.key.fixed_parameters)}</:col>
        </.table>
      </div>

      <div :if={@result.missing_on_prod != []}>
        <span class="text-warning font-bold text-xl">
          Records missing on PROD ({length(@result.missing_on_prod)})
        </span>
        <div class="text-sm text-base-content/50 max-w-3xl">
          Records marked as "pending sync" are new/renamed records that are expected to
          appear on prod after the next sync. Records without it claim to be synced,
          so they indicate a manual intervention (e.g. deleted on prod).
        </div>
        <.table id="missing_on_prod" rows={@result.missing_on_prod}>
          <:col :let={row} label="ID">{row.id}</:col>
          <:col :let={row} label="Metric">{row.key.metric}</:col>
          <:col :let={row} label="Data Type">{row.key.data_type}</:col>
          <:col :let={row} label="Fixed Parameters">{inspect(row.key.fixed_parameters)}</:col>
          <:col :let={row} label="Status">
            <.drift_status_badge pending_sync?={row.pending_sync?} />
          </:col>
        </.table>
      </div>

      <div :if={@result.changed != []}>
        <span class="text-warning font-bold text-xl">
          Records with different content ({length(@result.changed)})
        </span>
        <div class="text-sm text-base-content/50 max-w-3xl">
          The diff shows what needs to change on prod so it matches stage. Records
          marked as "pending sync" have local changes awaiting sync. Records without
          it claim to be synced, so they indicate a manual intervention on either side.
        </div>
        <.table id="changed" rows={@result.changed}>
          <:col :let={row} label="ID">{row.id}</:col>
          <:col :let={row} label="Metric">{row.key.metric}</:col>
          <:col :let={row} label="Status">
            <.drift_status_badge pending_sync?={row.pending_sync?} />
          </:col>
          <:col :let={row} label="Diff (prod -> stage)">
            {Sanbase.ExAudit.Patch.format_patch(%{patch: row.diff})}
          </:col>
        </.table>
      </div>
    </div>
    """
  end

  defp drift_status_badge(assigns) do
    ~H"""
    <span :if={@pending_sync?} class="badge badge-warning">pending sync</span>
    <span :if={!@pending_sync?} class="badge badge-error">manual drift</span>
    """
  end

  @impl true
  def handle_event("run_drift_check", _params, socket) do
    Permissions.raise_if_cannot(:run_sync_drift_check,
      roles: socket.assigns.current_user_role_names
    )

    {:noreply,
     socket
     |> assign(running?: true, error: nil)
     |> start_async(:drift_check, fn -> Drift.compute() end)}
  end

  @impl true
  def handle_async(:drift_check, {:ok, {:ok, result}}, socket) do
    {:noreply, assign(socket, result: result, running?: false)}
  end

  def handle_async(:drift_check, {:ok, {:error, error}}, socket) do
    {:noreply, assign(socket, error: error, running?: false)}
  end

  def handle_async(:drift_check, {:exit, reason}, socket) do
    {:noreply, assign(socket, error: "Drift check crashed: #{inspect(reason)}", running?: false)}
  end

  defp no_drift?(result) do
    result.missing_on_prod == [] and result.extra_on_prod == [] and result.changed == []
  end
end
