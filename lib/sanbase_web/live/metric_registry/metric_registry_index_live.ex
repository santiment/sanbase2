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
      <div class="text-gray-400 text-sm py-2">
        <div>
          Showing <%= length(@visible_metrics) %> metrics
        </div>
      </div>
      <.navigation />
      <.filters filter={@filter} />
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
          <.action_button text="Show" href={~p"/admin2/metric_registry/show/#{row.id}"} />
          <.action_button text="Edit" href={~p"/admin2/metric_registry/edit/#{row.id}"} />
        </:col>
      </AvailableMetricsComponents.table_with_popover_th>
    </div>
    """
  end

  def embeded_schema_show(assigns) do
    ~H"""
    <div>
      <div :for={item <- @list}>
        <%= Map.get(item, @key) %>
      </div>
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
      <form
        phx-change="apply_filters"
        class="flex flex-col flex-wrap space-y-2 items-start md:flex-row md:items-center md:gap-x-2 md:space-y-0"
      >
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

  defp maybe_apply_filter(metrics, _, _), do: metrics
end
