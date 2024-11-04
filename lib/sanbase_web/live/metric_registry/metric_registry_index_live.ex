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
       visible_metrics: metrics,
       metrics: metrics,
       filter: %{}
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col items-start justify-evenly">
      <.filters filter={@filter} />
      <div class="text-gray-400 text-sm py-2">
        <div>
          Showing <%= length(@visible_metrics) %> metrics
        </div>
      </div>
      <AvailableMetricsComponents.table_with_popover_th id="metrics_registry" rows={@visible_metrics}>
        <:col :let={row} label="ID">
          <%= row.id %>
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
          label="Min Interval"
          popover_target="popover-min-interval"
          popover_target_text={get_popover_text(%{key: "Frequency"})}
        >
          <%= row.min_interval %>
        </:col>
        <:col
          :let={row}
          label="Table"
          popover_target="popover-table"
          popover_target_text={get_popover_text(%{key: "Clickhouse Table"})}
        >
          <%= row.table %>
        </:col>
        <:col
          :let={row}
          label="Default Aggregation"
          popover_target="popover-default-aggregation"
          popover_target_text={get_popover_text(%{key: "Default Aggregation"})}
        >
          <%= row.aggregation %>
        </:col>
        <:col
          :let={row}
          label="Access"
          popover_target="popover-access"
          popover_target_text={get_popover_text(%{key: "Access"})}
        >
          <%= if is_map(row.access), do: Jason.encode!(row.access), else: row.access %>
        </:col>
        <:col
          :let={row}
          popover_target="popover-metric-details"
          popover_target_text={get_popover_text(%{key: "Metric Details"})}
        >
          <.action_button metric={row.metric} text="Show" href={~p"/metric_registry/show/#{row.id}"} />
          <.action_button metric={row.metric} text="Edit" href={~p"/metric_registry/edit/#{row.id}"} />
        </:col>
      </AvailableMetricsComponents.table_with_popover_th>
    </div>
    """
  end

  @impl true
  def handle_event("apply_filters", params, socket) do
    visible_metrics =
      socket.assigns.metrics
      |> maybe_apply_filter(:match_metric, params)
      |> maybe_apply_filter(:match_table, params)

    {:noreply,
     socket
     |> assign(
       visible_metrics: visible_metrics,
       filter: params
     )}
  end

  defp filters(assigns) do
    ~H"""
    <div>
      <form
        phx-change="apply_filters"
        class="flex flex-col flex-wrap space-y-2 items-start md:flex-row md:items-center md:gap-x-8"
      >
        <div>
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
      </form>
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

  defp action_button(assigns) do
    ~H"""
    <.link
      href={@href}
      class="text-gray-900 bg-white hover:bg-gray-100 border border-gray-200 font-medium rounded-lg text-sm px-5 py-2.5 text-center inline-flex items-center gap-x-2"
    >
      <%= @text %>
    </.link>
    """
  end

  defp metric_names(assigns) do
    ~H"""
    <div class="flex flex-col">
      <div class="text-black text-base"><%= @human_readable_name %></div>
      <div class="text-gray-900 text-sm"><%= @metric %> (API)</div>
      <div class="text-gray-900 text-sm"><%= @internal_metric %> (DB)</div>
    </div>
    """
  end

  defp maybe_apply_filter(metrics, :match_metric, %{"match_metric" => query})
       when query != "" do
    query = String.downcase(query)

    metrics
    |> Enum.filter(fn m ->
      String.contains?(m.metric, query) or
        String.contains?(m.internal_metric, query) or
        String.contains?(String.downcase(m.human_readable_name), query)
    end)
  end

  defp maybe_apply_filter(metrics, :match_table, %{"match_table" => query})
       when query != "" do
    metrics
    |> Enum.filter(fn m ->
      Enum.any?(m.table, &String.contains?(&1, query))
    end)
  end

  defp maybe_apply_filter(metrics, _, _), do: metrics
end
