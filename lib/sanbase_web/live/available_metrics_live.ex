defmodule SanbaseWeb.AvailableMetricsLive do
  use SanbaseWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    metrics_map = Sanbase.AvailableMetrics.get_metrics_map()

    default_filter = %{"only_with_non_empty_available_assets" => "on", "only_with_docs" => "on"}

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
    <div class="flex justify-center w-7/8">
      <div class="grid">
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
          <:col :let={row} label="API Name" min_width_class="md:min-w-[530px] break-words">
            <%= row.metric %>
          </:col>
          <:col :let={row} label="Internal Name" min_width_class="md:min-w-[510px] break-words">
            <%= row.internal_name %>
          </:col>
          <:col :let={row} label="Docs">
            <.docs_links docs={row.docs} />
          </:col>
          <:col :let={row} label="Frequency"><%= row.frequency %></:col>
          <:col :let={row} label="Available Assets" min_width_class="max-w-[200px]">
            <.available_assets assets={row.available_assets} />
          </:col>
          <:col :let={row}>
            <.metric_details_button metric={row.metric} />
          </:col>
        </.table>
      </div>
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

  defp filters(assigns) do
    ~H"""
    <div>
      <form phx-change="apply_filters" class="flex space-x-8 items-center justify-start">
        <div class="flex items-center">
          <input
            id="with-assets-checkbox"
            type="checkbox"
            name="only_with_non_empty_available_assets"
            checked={@filter["only_with_non_empty_available_assets"] == "on"}
            class="w-4 h-4 border-gray-300 rounded"
          />
          <label for="with-assets-checkbox" class="ms-2 text-sm font-medium text-gray-900">
            Only with non-empty available metrics
          </label>
        </div>

        <div class="flex items-center">
          <input
            id="with-docs-checkbox"
            type="checkbox"
            name="only_with_docs"
            checked={@filter["only_with_docs"] == "on"}
            class="w-4 h-4 border-gray-300 rounded"
          />
          <label for="with-docs-checkbox" class="ms-2 text-sm font-medium text-gray-900">
            Only with docs
          </label>
        </div>

        <div class="flex items-center">
          <input
            id="with-intraday-checkbox"
            type="checkbox"
            name="only_intraday_metrics"
            checked={@filter["only_intraday_metrics"] == "on"}
            class="w-4 h-4 border-gray-300 rounded"
          />
          <label for="with-intraday-checkbox" class="ms-2 text-sm font-medium text-gray-900">
            Only with intraday frequency
          </label>
        </div>

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

        <.link
          href={~p"/export_available_metrics?#{%{filter: Jason.encode!(@filter)}}"}
          class={button_style()}
        >
          <.icon name="hero-arrow-down-tray" />
          <span>Download as CSV</span>
        </.link>
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
      <a :for={doc <- assigns.docs} href={doc.link} target="_blank">
        Open Docs
      </a>
    </div>
    """
  end

  defp metric_details_button(assigns) do
    ~H"""
    <.link href={~p"/available_metrics/#{@metric}"} class={button_style()}>
      <.icon name="hero-arrow-top-right-on-square" class="text-gray-500" />
      <span>Open</span>
    </.link>
    """
  end

  defp button_style() do
    "text-gray-900 bg-white hover:bg-gray-100 border border-gray-200 font-medium rounded-lg text-sm px-5 py-2.5 text-center inline-flex items-center gap-x-2"
  end
end