defmodule SanbaseWeb.AvailableMetricsLive do
  use SanbaseWeb, :live_view

  import SanbaseWeb.AvailableMetricsComponents

  @impl true
  def mount(_params, _session, socket) do
    metrics_map = Sanbase.AvailableMetrics.get_metrics_map()

    default_filter = %{"only_asset_metrics" => "on", "only_with_docs" => "on"}

    visible_metrics =
      metrics_map
      |> Sanbase.AvailableMetrics.apply_filters(default_filter)
      |> Enum.map(& &1.metric)

    {:ok,
     socket
     |> assign(
       visible_metrics: visible_metrics,
       metrics_map: metrics_map,
       filter: default_filter
     )}
  end

  @impl true
  def render(assigns) do
    ordered_visible_metrics =
      Map.take(assigns.metrics_map, assigns.visible_metrics)
      |> Map.values()
      |> Enum.sort_by(& &1.metric, :asc)

    total_assets_with_metrics =
      Enum.reduce(
        ordered_visible_metrics,
        MapSet.new(),
        &MapSet.union(MapSet.new(&1.available_assets), &2)
      )
      |> MapSet.size()

    assigns =
      assigns
      |> assign(
        ordered_visible_metrics: ordered_visible_metrics,
        assets_count: total_assets_with_metrics
      )

    ~H"""
    <div class="flex flex-col items-start justify-evenly">
      <.filters filter={@filter} />
      <div class="text-gray-400 text-sm py-2">
        <div>
          Showing <%= length(@visible_metrics) %> metrics
        </div>
        <div>
          In total <%= to_string(@assets_count) %> assets are supported by at least one of the visible filtered metrics
        </div>
      </div>
      <.table id="available_metrics" rows={@ordered_visible_metrics}>
        <:col :let={row} label="Name">
          <%= row.metric %>
        </:col>
        <:col :let={row} :if={@filter["show_internal_name"] == "on"} label="Internal Name">
          <%= row.internal_name %>
        </:col>
        <:col :let={row} label="Frequency"><%= row.frequency %></:col>
        <:col :let={row} label="Selectors">
          <.available_selectors selectors={row.available_selectors} />
        </:col>
        <:col :let={row} label="Default Aggregation">
          <%= row.default_aggregation |> to_string() |> String.upcase() %>
        </:col>
        <:col :let={row} label="Available Assets" col_class="max-w-[200px]">
          <.available_assets assets={row.available_assets} />
        </:col>
        <:col :let={row} label="Docs">
          <.docs_links docs={row.docs} />
        </:col>
        <:col :let={row} label="Metric Details">
          <.metric_details_button metric={row.metric} />
        </:col>
      </.table>
    </div>
    """
  end

  @impl true
  def handle_event("apply_filters", params, socket) do
    visible_metrics =
      socket.assigns.metrics_map
      |> Sanbase.AvailableMetrics.apply_filters(params)
      |> Enum.map(& &1.metric)

    {:noreply,
     socket
     |> assign(
       visible_metrics: visible_metrics,
       filter: params
     )}
  end

  attr :popover_text, :string, required: true
  attr :popover_target, :string, required: true
  attr :input_id, :string, required: true
  attr :input_name, :string, required: true
  attr :input_checked, :boolean, required: true
  attr :input_label, :string, required: true

  def checkbox_with_popover(assigns) do
    ~H"""
    <div class="relative flex items-center">
      <input
        id={@input_id}
        type="checkbox"
        name={@input_name}
        checked={@input_checked}
        class="w-4 h-4 border-gray-300 rounded hover:cursor-pointer"
        data-popover-target={@popover_target}
        data-popover-style="light"
      />
      <label
        for={@input_id}
        class="ms-2 text-sm font-medium text-gray-900 border-b border-dotted hover:cursor-pointer"
        data-popover-target={@popover_target}
        data-popover-style="light"
      >
        <%= @input_label %>
      </label>
      <div
        id={@popover_target}
        role="tooltip"
        class="absolute top-4 right-10 z-10 w-80 text-justify invisible inline-block px-8 py-6 text-sm font-medium text-gray-600 bg-white border border-gray-200 rounded-lg shadow-sm opacity-0 popover sans"
      >
        <span><%= @popover_text %></span>
        <div class="popover-arrow" data-popper-arrow></div>
      </div>
    </div>
    """
  end

  defp filters(assigns) do
    ~H"""
    <div>
      <form
        phx-change="apply_filters"
        class="flex flex-col flex-wrap space-y-2 items-start md:flex-row md:items-center md:gap-x-8"
      >
        <.checkbox_with_popover
          popover_text="Show the metrics that are available for assets. Exlude metrics that are computed only for other selectors like ecosystem, contracts, etc."
          popover_target="popover-with-assets"
          input_id="with-assets-checkbox"
          input_name="only_asset_metrics"
          input_checked={@filter["only_asset_metrics"] == "on"}
          input_label="Filter asset metrics"
        />

        <.checkbox_with_popover
          popover_text="Show only the metrics that have documentation"
          popover_target="popover-with-docs"
          input_id="with-docs-checkbox"
          input_name="only_with_docs"
          input_checked={@filter["only_with_docs"] == "on"}
          input_label="Only with docs"
        />
        <.checkbox_with_popover
          popover_text="The internal name is the name of the metric used in the databse tables. This is of interest only for Santiment Queries"
          popover_target="popover-show-internal-name"
          input_id="show-internal-name"
          input_name="show_internal_name"
          input_checked={@filter["show_internal_name"] == "on"}
          input_label="Show internal name"
        />

        <div>
          <input
            type="search"
            id="metric-name-search"
            value={@filter["match_metric_name"] || ""}
            name="match_metric_name"
            class="block w-64 ps-4 text-sm text-gray-900 border border-gray-300 rounded-lg bg-white"
            placeholder="Filter by metric"
            phx-debounce="200"
          />
        </div>

        <div>
          <input
            type="search"
            id="metric-supports_asset"
            value={@filter["metric_supports_asset"] || ""}
            name="metric_supports_asset"
            class="block w-64 ps-4 text-sm text-gray-900 border border-gray-300 rounded-lg bg-white"
            placeholder="Filter by supported asset"
            phx-debounce="200"
          />
        </div>
        <.available_metrics_button
          text="Download as CSV"
          icon="hero-arrow-down-tray"
          href={~p"/export_available_metrics?#{%{filter: Jason.encode!(@filter)}}"}
        />
      </form>
    </div>
    """
  end

  defp available_assets(assigns) do
    {first_2, rest} = Enum.split(assigns.assets, 2)
    first_2_str = Enum.join(first_2, ", ")

    rest_str = if rest != [], do: " and #{length(rest)} more", else: ""

    assigns =
      assigns
      |> assign(first_2_str: first_2_str, rest_str: rest_str)

    ~H"""
    <span>
      <%= @first_2_str %>
      <span class="text-gray-400"><%= @rest_str %></span>
    </span>
    """
  end

  defp docs_links(assigns) do
    ~H"""
    <div class="flex flex-row">
      <.available_metrics_button
        :for={doc <- assigns.docs}
        href={doc.link}
        text="Docs"
        icon="hero-clipboard-document-list"
      />
    </div>
    """
  end

  defp metric_details_button(assigns) do
    ~H"""
    <.available_metrics_button
      text="Details"
      href={~p"/available_metrics/#{@metric}"}
      icon="hero-arrow-top-right-on-square"
    />
    """
  end

  defp available_selectors(assigns) do
    ~H"""
    <pre>
    <%= @selectors
    |> List.wrap()
    |> Enum.map(fn x -> x |> to_string() |> String.upcase() end)
    |> Enum.join("\n") %>
    </pre>
    """
  end
end
