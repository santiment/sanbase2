defmodule SanbaseWeb.MetricRegistryIndexLive do
  use SanbaseWeb, :live_view

  import SanbaseWeb.AvailableMetricsDescription
  alias SanbaseWeb.AvailableMetricsComponents

  @impl true
  def mount(_params, _session, socket) do
    metrics = Sanbase.Metric.Registry.all()

    {:ok,
     socket
     |> assign(
       show_verified_changes_modal: false,
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
      <div class="text-gray-400 text-sm py-2">
        <div>
          Showing <%= length(@visible_metrics_ids) %> metrics
        </div>
      </div>
      <.navigation />
      <.filters filter={@filter} changed_metrics_ids={@changed_metrics_ids} />
      <AvailableMetricsComponents.table_with_popover_th
        id="metrics_registry"
        rows={Enum.filter(@metrics, &(&1.id in @visible_metrics_ids))}
      >
        <:col :let={row} label="ID">
          {row.id}
        </:col>
        <:col :let={row} label="Metric Names" col_class="max-w-[480px] break-all">
          <.metric_names
            metric={row.metric}
            internal_metric={row.internal_metric}
            human_readable_name={row.human_readable_name}
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
<<<<<<< HEAD
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
||||||| parent of e83704e2d (Add is_verified toggle to Metric Registry LiveView)
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
          <%= row.default_aggregation %>
        </:col>
        <:col
          :let={row}
=======
>>>>>>> e83704e2d (Add is_verified toggle to Metric Registry LiveView)
          label="Access"
          popover_target="popover-access"
          popover_target_text={get_popover_text(%{key: "Access"})}
        >
          {if is_map(row.access), do: Jason.encode!(row.access), else: row.access}
        </:col>
        <:col :let={row} label="Status">
          <.verified_toggle row={row} />
        </:col>
        <:col
          :let={row}
          popover_target="popover-metric-details"
          popover_target_text={get_popover_text(%{key: "Metric Details"})}
        >
          <.action_button text="Show" href={~p"/admin2/metric_registry/show/#{row.id}"} />
          <.action_button text="Edit" href={~p"/admin2/metric_registry/edit/#{row.id}"} />
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
      |> maybe_apply_filter(:match_table, params)
      |> maybe_apply_filter(:only_unverified, params)
      |> Enum.map(& &1.id)

    {:noreply,
     socket
     |> assign(
       visible_metrics_ids: visible_metrics_ids,
       filter: params
     )}
  end

  def handle_event("show_verified_changes_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(show_verified_changes_modal: true)}
  end

  def handle_event("hide_show_verified_changes_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(show_verified_changes_modal: false)}
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
        Sanbase.Metric.Registry.update(
          %{metric | is_verified: map.old},
          %{is_verified: map.new},
          emit_event: false
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

  defp list_metrics_verified_status_changed(assigns) do
    ~H"""
<<<<<<< HEAD
    <div>
      <div :for={item <- @list}>
        {Map.get(item, @key)}
||||||| parent of e83704e2d (Add is_verified toggle to Metric Registry LiveView)
    <div>
      <div :for={item <- @list}>
        <%= Map.get(item, @key) %>
=======
    <div :if={@changed_metrics_ids == []}>
      No changes
    </div>
    <div :if={@changed_metrics_ids != []}>
      <.table id="uploaded_images" rows={Enum.filter(@metrics, &(&1.id in @changed_metrics_ids))}>
        <:col :let={row} label="Metric">
          <.metric_names
            metric={row.metric}
            internal_metric={row.internal_metric}
            human_readable_name={row.human_readable_name}
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
        />
        <.phx_click_button
          phx_click="hide_show_verified_changes_modal"
          class="bg-white hover:bg-gray-100 text-gray-800"
          text="Close"
        />
>>>>>>> e83704e2d (Add is_verified toggle to Metric Registry LiveView)
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

  defp navigation(assigns) do
    ~H"""
    <div class="my-2">
      <div>
        <.action_button
          icon="hero-plus"
          text="Create New Metric"
          href={~p"/admin2/metric_registry/new"}
        />
        <.action_button
          icon="hero-list-bullet"
          text="See Change Suggestions"
          href={~p"/admin2/metric_registry/change_suggestions"}
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

          <.filter_input
            id="table-search"
            value={@filter["match_table"]}
            name="match_table"
            placeholder="Filter by table"
          />
        </div>
        <div class="flex flex-col flex-wrap mt-4 space-y-2 items-start">
          <.filter_not_verified />
        </div>
      </form>
      <.phx_click_button
        phx_click="show_verified_changes_modal"
        class="text-gray-900 bg-white hover:bg-gray-100"
        text="Apply Verified Status Changes"
        count={length(@changed_metrics_ids)}
      />
    </div>
    """
  end

  defp filter_not_verified(assigns) do
    ~H"""
    <div class="flex items-center mb-4 ">
      <input
        id="not-verified-only"
        name="not_verified_only"
        type="checkbox"
        class="w-4 h-4 text-blue-600 bg-gray-100 border-gray-300 rounded "
      />
      <label for="default-checkbox" class="ms-2 text-sm font-medium text-gray-900 dark:text-gray-300">
        Show Not Verified Only
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

  attr :href, :string, required: true
  attr :text, :string, required: true
  attr :icon, :string, required: false, default: nil

  defp action_button(assigns) do
    ~H"""
    <.link
      href={@href}
      class="text-gray-900 bg-white hover:bg-gray-100 border border-gray-200 font-medium rounded-lg text-sm px-5 py-2.5 text-center inline-flex items-center gap-x-2"
    >
      <.icon :if={@icon} name={@icon} />
      {@text}
    </.link>
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
      <%= @text %>
      <span :if={@count} class="text-gray-400">(<%= @count %>)</span>
    </button>
    """
  end

  defp metric_names(assigns) do
    ~H"""
    <div class="flex flex-col">
      <div class="text-black text-base">{@human_readable_name}</div>
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

  defp maybe_apply_filter(metrics, :match_table, %{"match_table" => query})
       when query != "" do
    metrics
    |> Enum.filter(fn m ->
      Enum.any?(m.tables, &String.contains?(&1.name, query))
    end)
  end

  defp maybe_apply_filter(metrics, :match_table, %{"not_verified_only" => "on"}) do
    metrics
    |> Enum.filter(fn m ->
      m.is_verified == false
    end)
  end

  defp maybe_apply_filter(metrics, _, _), do: metrics
end
