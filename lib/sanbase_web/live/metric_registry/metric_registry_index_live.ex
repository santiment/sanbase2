defmodule SanbaseWeb.MetricRegistryIndexLive do
  use SanbaseWeb, :live_view

  import SanbaseWeb.AvailableMetricsDescription

  alias Sanbase.Metric.Registry.Permissions
  alias SanbaseWeb.AvailableMetricsComponents

  @impl true
  def mount(_params, _session, socket) do
    # Load the metrics only when connected
    # We don't care about SEO here. Loadin on non-connected makes it so
    # if someone is fast to click on Verified Status toggle, the action
    # gets discarded on the connection
    metrics = if connected?(socket), do: Sanbase.Metric.Registry.all(), else: []

    {:ok,
     socket
     |> assign(
       page_title: "Metric Registry",
       show_verified_changes_modal: false,
       show_not_synced_diff: false,
       not_synced_metric_registry: nil,
       visible_metrics_ids: Enum.map(metrics, & &1.id),
       metrics: metrics,
       changed_metrics_ids: [],
       verified_metrics_updates_map: %{},
       filter: %{}
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.modal
      :if={@show_not_synced_diff}
      show
      id="not_synced_diff"
      max_modal_width="max-w-6xl"
      on_cancel={JS.push("hide_show_not_synced_diff")}
    >
      <.diff_since_last_sync metric_registry={@not_synced_metric_registry} />
    </.modal>

    <.modal
      :if={@show_verified_changes_modal}
      show
      id="verified_changes_modal"
      max_modal_width="max-w-6xl"
      on_cancel={JS.push("hide_show_verified_changes_modal")}
    >
      <.list_metrics_verified_status_changed
        changed_metrics_ids={@changed_metrics_ids}
        metrics={@metrics}
      />
    </.modal>
    <div class="flex flex-col items-start justify-evenly">
      <h1 class="text-blue-700 text-2xl mb-4">
        Metric Registry Index
      </h1>
      <SanbaseWeb.MetricRegistryComponents.user_details
        current_user={@current_user}
        current_user_role_names={@current_user_role_names}
      />
      <div class="text-gray-400 text-sm py-2">
        <div>
          Showing {length(@visible_metrics_ids)} metrics
        </div>
      </div>
      <.navigation current_user_role_names={@current_user_role_names} />
      <.filters
        filter={@filter}
        changed_metrics_ids={@changed_metrics_ids}
        current_user_role_names={@current_user_role_names}
      />
      <AvailableMetricsComponents.table_with_popover_th
        id="metrics_registry"
        rows={take_ordered(@metrics, @visible_metrics_ids)}
      >
        <:col :let={row} label="ID">
          {row.id}
        </:col>
        <:col :let={row} label="Metric Names" col_class="max-w-[420px]">
          <.metric_names
            metric={row.metric}
            internal_metric={row.internal_metric}
            human_readable_name={row.human_readable_name}
            status={row.status}
          />
        </:col>
        <:col
          :let={row}
          label="Frequency"
          popover_target="popover-min-interval"
          popover_target_text={get_popover_text(%{key: "Frequency"})}
        >
          {row.min_interval}
        </:col>
        <:col
          :let={row}
          label="Table"
          popover_target="popover-table"
          popover_target_text={get_popover_text(%{key: "Clickhouse Table"})}
        >
          <.embeded_schema_show list={row.tables} key={:name} />
        </:col>
        <:col
          :let={row}
          label="Default Aggregation"
          popover_target="popover-default-aggregation"
          popover_target_text={get_popover_text(%{key: "Default Aggregation"})}
        >
          {row.default_aggregation}
        </:col>
        <:col
          :let={row}
          label="Access"
          popover_target="popover-access"
          popover_target_text={get_popover_text(%{key: "Access"})}
        >
          {if is_map(row.access), do: Jason.encode!(row.access), else: row.access}
        </:col>
        <:col
          :let={row}
          :if={Permissions.can?(:access_verified_status, roles: @current_user_role_names)}
          label="Verified Status"
          popover_target="popover-verified-status"
          popover_target_text={get_popover_text(%{key: "Verified Status"})}
        >
          <.verified_toggle row={row} />
        </:col>

        <:col
          :let={row}
          :if={Permissions.can?(:access_sync_status, roles: @current_user_role_names)}
          label="Sync Status"
          popover_target="popover-sync-status"
          popover_target_text={get_popover_text(%{key: "Sync Status"})}
        >
          <.sync_status row={row} />
        </:col>
        <:col
          :let={row}
          popover_target="popover-metric-details"
          popover_target_text={get_popover_text(%{key: "Metric Details"})}
        >
          <AvailableMetricsComponents.link_button
            text="Show"
            href={~p"/admin2/metric_registry/show/#{row.id}"}
          />
          <AvailableMetricsComponents.link_button
            :if={Permissions.can?(:edit, roles: @current_user_role_names)}
            text="Edit"
            href={~p"/admin2/metric_registry/edit/#{row.id}"}
          />

          <AvailableMetricsComponents.link_button
            :if={Permissions.can?(:edit, roles: @current_user_role_names)}
            text="Duplicate"
            href={~p"/admin2/metric_registry/new?#{%{duplicate_metric_registry_id: row.id}}"}
          />
        </:col>
      </AvailableMetricsComponents.table_with_popover_th>
    </div>
    """
  end

  @impl true
  def handle_event("apply_filters", params, socket) do
    visible_metrics_ids =
      socket.assigns.metrics
      |> maybe_apply_filter(:match_metric, params)
      |> maybe_apply_filter(:unverified_only, params)
      |> maybe_apply_filter(:not_synced_only, params)
      |> Enum.map(& &1.id)

    {:noreply,
     socket
     |> assign(
       visible_metrics_ids: visible_metrics_ids,
       filter: params
     )}
  end

  def handle_event("show_verified_changes_modal", _params, socket) do
    {:noreply, socket |> assign(show_verified_changes_modal: true)}
  end

  def handle_event("hide_show_verified_changes_modal", _params, socket) do
    {:noreply, socket |> assign(show_verified_changes_modal: false)}
  end

  def handle_event("show_not_synced_diff", %{"metric_registry_id" => id}, socket) do
    {:noreply,
     socket
     |> assign(
       show_not_synced_diff: true,
       not_synced_metric_registry: Enum.find(socket.assigns.metrics, &(&1.id == id))
     )}
  end

  def handle_event("hide_show_not_synced_diff", _params, socket) do
    {:noreply, socket |> assign(show_not_synced_diff: false)}
  end

  def handle_event(
        "update_status_is_verified",
        %{"metric_registry_id" => id, "is_verified" => bool},
        socket
      ) do
    verified_metrics_updates_map =
      Map.update(
        socket.assigns.verified_metrics_updates_map,
        id,
        # This will be invoked only the first time the metric registry is updated
        %{old: Enum.find(socket.assigns.metrics, &(&1.id == id)).is_verified, new: bool},
        fn map -> Map.put(map, :new, bool) end
      )

    # Keep only the IDs and not the full metric list otherwise this list needs to be
    # updated after each time update_metric/4 is called or the metrics list is mutated
    # in any other way.
    changed_metrics_ids =
      verified_metrics_updates_map
      |> Enum.reduce([], fn {id, map}, acc ->
        if map.new != map.old, do: [id | acc], else: acc
      end)

    {:noreply,
     assign(socket,
       changed_metrics_ids: changed_metrics_ids,
       verified_metrics_updates_map: verified_metrics_updates_map,
       metrics: update_metric(socket.assigns.metrics, id, :is_verified, bool)
     )}
  end

  def handle_event("confirm_verified_changes_update", _params, socket) do
    for metric <- socket.assigns.metrics, metric.id in socket.assigns.changed_metrics_ids do
      map = Map.get(socket.assigns.verified_metrics_updates_map, metric.id)

      # Explicitly put the old is_verified status in the first argument otherwise Ecto
      # will decide that the value does not change and will not mutate the DB
      {:ok, _} =
        Sanbase.Metric.Registry.update_is_verified(
          # Put the old is_verified here so after a few toggles we still know
          # how it started
          %{metric | is_verified: map.old},
          map.new
        )
    end

    {:noreply,
     socket
     |> assign(
       changed_metrics_ids: [],
       verified_metrics_updates_map: %{},
       show_verified_changes_modal: false
     )
     |> put_flash(
       :info,
       "Suggessfully updated the is_verified status of #{length(socket.assigns.changed_metrics_ids)} metric metricss"
     )}
  end

  defp embeded_schema_show(assigns) do
    ~H"""
    <div>
      <div :for={item <- @list}>
        {Map.get(item, @key)}
      </div>
    </div>
    """
  end

  defp diff_since_last_sync(assigns) do
    with {:ok, old_state_json} <-
           Sanbase.Metric.Registry.Changelog.state_before_last_sync(
             assigns.metric_registry.id,
             assigns.metric_registry.last_sync_datetime
           ) do
      metric_registry_map = Jason.encode!(assigns.metric_registry) |> Jason.decode!()

      diff_changes =
        ExAudit.Diff.diff(old_state_json, metric_registry_map)

      html_safe_changes = Sanbase.ExAudit.Patch.format_patch(%{patch: diff_changes})

      assigns = assign(assigns, :html_safe_changes, html_safe_changes)

      ~H"""
      <div :if={@metric_registry.last_sync_datetime} class="font-bold text-xl text-blue-800 mb-4">
        Diff Since Last Sync | {@metric_registry.metric}
      </div>
      <div :if={!@metric_registry.last_sync_datetime} class="font-bold text-gray-400 text-sm mb-4">
        Diff Since Metric Creation | {@metric_registry.metric}
      </div>
      <div>{@html_safe_changes}</div>
      """
    else
      _err ->
        ~H"""
        <div>
          <div>
            This should not be visible.
          </div>
          <div>
            This can be caused because some things were done on staging before some of the helper database tables were introduced.
            <br /> If you see this message contact the backend team and share the following details:
          </div>
          <div>
            Metric Id: {@metric_registry.id}
          </div>
          <div>
            Metric Name: {@metric_registry.metric}
          </div>

          <div class="text-wrap break-words ">
            {:erlang.term_to_binary(@metric_registry) |> Base.encode64()}
          </div>
        </div>
        """
    end
  end

  defp list_metrics_verified_status_changed(assigns) do
    ~H"""
    <div>
      <div :if={@changed_metrics_ids == []}>
        No changes.
        Change the verified status of one or more metrics.
      </div>
      <div :if={@changed_metrics_ids != []}>
        <.table
          id="confirm_verified_changes_update_table"
          rows={Enum.filter(@metrics, &(&1.id in @changed_metrics_ids))}
        >
          <:col :let={row} label="Metric" col_class="max-w-[420px]">
            <.metric_names
              metric={row.metric}
              internal_metric={row.internal_metric}
              human_readable_name={row.human_readable_name}
              status={row.status}
            />
          </:col>
          <:col :let={row} label="New Status">
            <span :if={row.is_verified} class="ms-3 text-sm font-bold text-green-900">VERIFIED</span>
            <span :if={!row.is_verified} class="ms-3 text-sm font-bold text-red-700">UNVERIFIED</span>
          </:col>
        </.table>
        <div class="mt-4">
          <.phx_click_button
            phx_click="confirm_verified_changes_update"
            class="bg-green-500 hover:bg-green-900 text-white"
            text="Confirm Changes"
            count={length(@changed_metrics_ids)}
          />
          <.phx_click_button
            phx_click="hide_show_verified_changes_modal"
            class="bg-white hover:bg-gray-100 text-gray-800"
            text="Close"
          />
        </div>
      </div>
    </div>
    """
  end

  defp verified_toggle(assigns) do
    ~H"""
    <label class="inline-flex items-center me-5 cursor-pointer">
      <input
        type="checkbox"
        class="sr-only peer"
        checked={@row.is_verified}
        phx-click={
          JS.push("update_status_is_verified",
            value: %{metric_registry_id: @row.id, is_verified: !@row.is_verified}
          )
        }
      />
      <div class="relative w-11 h-6 bg-red-500 rounded-full peer peer-checked:after:translate-x-full rtl:peer-checked:after:-translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-0.5 after:start-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-green-600">
      </div>
      <span :if={@row.is_verified} class="ms-3 text-sm font-bold text-green-900">VERIFIED</span>
      <span :if={!@row.is_verified} class="ms-3 text-sm font-bold text-red-700">UNVERIFIED</span>
    </label>
    """
  end

  def sync_status(assigns) do
    ~H"""
    <div>
      <span :if={@row.sync_status == "synced"} class="text-green-900 ms-3 text-sm font-bold">
        SYNCED
      </span>

      <span :if={@row.sync_status == "not_synced"} class="text-red-700 ms-3 text-sm font-bold">
        <div>NOT SYNCED</div>
      </span>

      <div
        :if={@row.sync_status == "not_synced"}
        class="text-gray-400 text-sm font-semibold cursor-pointer"
        phx-click={JS.push("show_not_synced_diff", value: %{metric_registry_id: @row.id})}
      >
        (click to see diff)
      </div>
    </div>
    """
  end

  defp navigation(assigns) do
    ~H"""
    <div class="my-2">
      <div>
        <AvailableMetricsComponents.link_button
          :if={Permissions.can?(:create, roles: @current_user_role_names)}
          icon="hero-plus"
          text="Create New Metric"
          href={~p"/admin2/metric_registry/new"}
        />
        <AvailableMetricsComponents.link_button
          icon="hero-list-bullet"
          text="See Change Requests"
          href={~p"/admin2/metric_registry/change_suggestions"}
        />

        <AvailableMetricsComponents.link_button
          :if={Permissions.can?(:start_sync, roles: @current_user_role_names)}
          icon="hero-arrow-path-rounded-square"
          text="Sync Metrics"
          href={~p"/admin2/metric_registry/sync"}
        />

        <AvailableMetricsComponents.available_metrics_button
          :if={Permissions.can?(:see_sync_runs, roles: @current_user_role_names)}
          text="List Sync Runs"
          href={~p"/admin2/metric_registry/sync_runs"}
          icon="hero-list-bullet"
        />

        <AvailableMetricsComponents.link_button
          icon="hero-document-text"
          text="Docs"
          href="https://github.com/santiment/sanbase2/blob/master/docs/metric_registry/index.md"
          target="_blank"
        />
      </div>
    </div>
    """
  end

  defp filters(assigns) do
    ~H"""
    <div>
      <span class="text-sm font-semibold leading-6 text-zinc-800">Filters</span>
      <form phx-change="apply_filters">
        <div class="flex flex-col flex-wrap space-y-2 items-start md:flex-row md:items-center md:gap-x-2 md:space-y-0">
          <.filter_input
            id="metric-name-search"
            value={@filter["match_metric"]}
            name="match_metric"
            placeholder="Filter by metric name"
          />

          <.filter_status value={@filter["status"]} />
        </div>
        <div class="flex flex-row mt-4 space-x-2 ">
          <.filter_unverified />
          <.filter_not_synced />
        </div>
      </form>
      <.phx_click_button
        :if={Permissions.can?(:access_verified_status, roles: @current_user_role_names)}
        phx_click="show_verified_changes_modal"
        class={
          if(@changed_metrics_ids == [],
            do: "text-gray-900 bg-white hover:bg-gray-100",
            else: "border border-green-700 text-white bg-green-500 hover:bg-green-600"
          )
        }
        text="Apply Verified Status Changes"
        count={length(@changed_metrics_ids)}
      />
    </div>
    """
  end

  defp filter_unverified(assigns) do
    ~H"""
    <div class="flex items-center mb-4 ">
      <label for="unverified-only" class="cursor-pointer ms-2 text-sm font-medium text-gray-900">
        <input
          id="unverified-only"
          name="unverified_only"
          type="checkbox"
          class="w-4 h-4 text-blue-600 bg-gray-100 border-gray-300 rounded "
        /> Show Only Unverified
      </label>
    </div>
    """
  end

  defp filter_not_synced(assigns) do
    ~H"""
    <div class="flex items-center mb-4 ">
      <label
        for="not-synced-only"
        class="cursor-pointer ms-2 text-sm font-medium text-gray-900 dark:text-gray-300"
      >
        <input
          id="not-synced-only"
          name="not_synced_only"
          type="checkbox"
          class="w-4 h-4 text-blue-600 bg-gray-100 border-gray-300 rounded "
        /> Show Only Not Synced
      </label>
    </div>
    """
  end

  defp filter_input(assigns) do
    ~H"""
    <input
      type="search"
      id={@id}
      value={@value || ""}
      name={@name}
      class="block w-64 ps-4 text-sm text-gray-900 border border-gray-300 rounded-lg bg-white"
      placeholder={@placeholder}
      phx-debounce="200"
    />
    """
  end

  defp filter_status(assigns) do
    ~H"""
    <select
      name="status"
      class="block w-48 ps-4 text-sm text-gray-900 border border-gray-300 rounded-lg bg-white"
    >
      <option value="">All Statuses</option>
      <option
        :for={status <- Sanbase.Metric.Registry.allowed_statuses()}
        value={status}
        selected={@value == status}
      >
        {String.capitalize(status)}
      </option>
    </select>
    """
  end

  attr :phx_click, :string, required: true
  attr :text, :string, required: true
  attr :count, :integer, required: false, default: nil
  attr :class, :string, required: true

  defp phx_click_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click={@phx_click}
      class={[
        "border border-gray-200 font-medium rounded-lg text-sm px-5 py-2.5 text-center inline-flex items-center gap-x-2",
        @class
      ]}
    >
      {@text}
      <span :if={@count > 0} class="text-white">({@count})</span>
    </button>
    """
  end

  defp metric_names(assigns) do
    ~H"""
    <div class="flex flex-col break-normal">
      <div class="text-black text-base">
        {@human_readable_name}
        <span
          :if={@status in ["alpha", "beta"]}
          class={if @status == "alpha", do: "text-amber-600 text-sm", else: "text-violet-600 text-sm"}
        >
          ({String.upcase(@status)})
        </span>
      </div>
      <div class="text-gray-900 text-sm">{@metric} (API)</div>
      <div class="text-gray-900 text-sm">{@internal_metric} (DB)</div>
    </div>
    """
  end

  defp update_metric(metrics, id, key, value) do
    Enum.map(metrics, fn metric ->
      if metric.id == id do
        %{metric | key => value}
      else
        metric
      end
    end)
  end

  defp maybe_apply_filter(metrics, :match_metric, %{"match_metric" => query})
       when query != "" do
    query = String.downcase(query)
    query_parts = String.split(query)

    metrics
    |> Enum.filter(fn m ->
      Enum.all?(query_parts, fn part -> String.contains?(m.metric, part) end) or
        Enum.all?(query_parts, fn part -> String.contains?(m.internal_metric, part) end) or
        Enum.all?(query_parts, fn part ->
          String.contains?(String.downcase(m.human_readable_name), part)
        end)
    end)
    |> Enum.sort_by(&String.jaro_distance(query, &1.metric), :desc)
  end

  defp maybe_apply_filter(metrics, :unverified_only, %{"unverified_only" => "on"}) do
    metrics
    |> Enum.filter(fn m ->
      m.is_verified == false
    end)
  end

  defp maybe_apply_filter(metrics, :not_synced_only, %{"not_synced_only" => "on"}) do
    metrics
    |> Enum.filter(fn m ->
      m.sync_status != "synced"
    end)
  end

  defp maybe_apply_filter(metrics, :match_metric, %{"status" => status}) when status != "" do
    metrics
    |> Enum.filter(fn m ->
      m.status == status
    end)
  end

  defp maybe_apply_filter(metrics, _, _), do: metrics

  defp take_ordered(metrics, ids) do
    metrics_map = Map.new(metrics, &{&1.id, &1})
    Enum.map(ids, &Map.get(metrics_map, &1))
  end
end
