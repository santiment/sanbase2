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
        <:col
          :let={row}
          label="Metric"
          popover_target="popover-metric"
          popover_target_text={get_popover_text(%{key: "Name"})}
          col_class="max-w-[320px] break-all"
        >
          <%= row.metric %>
        </:col>
        <:col
          :let={row}
          label="Internal Metric"
          popover_target="popover-internal-name"
          popover_target_text={get_popover_text(%{key: "Internal Name"})}
          col_class="max-w-[320px] break-all"
        >
          <%= row.internal_metric %>
        </:col>
        <:col
          :let={row}
          label="Selectors"
          popover_target="popover-selectors"
          popover_target_text={get_popover_text(%{key: "Available Selectors"})}
        >
          <.available_selectors selectors={row.selectors} />
        </:col>
        <:col
          :let={row}
          label="Default Aggregation"
          popover_target="popover-default-aggregation"
          popover_target_text={get_popover_text(%{key: "Default Aggregation"})}
        >
          <%= row.aggregation |> to_string() |> String.upcase() %>
        </:col>
        <:col
          :let={row}
          label="Access"
          popover_target="popover-access"
          popover_target_text={get_popover_text(%{key: "Access"})}
        >
          <.metric_access access={row.access} />
        </:col>
        <:col
          :let={row}
          popover_target="popover-metric-details"
          popover_target_text={get_popover_text(%{key: "Metric Details"})}
        >
          <.action_button
            metric={row.metric}
            text="Show"
            href={~p"/metric_registry/show/#{row.metric}"}
          />
          <.action_button
            metric={row.metric}
            text="Edit"
            href={~p"/metric_registry/edit/#{row.metric}"}
          />
        </:col>
      </AvailableMetricsComponents.table_with_popover_th>
    </div>
    """
  end

  @impl true
  def handle_event("apply_filters", params, socket) do
    visible_metrics =
      socket.assigns.metrics
      |> Sanbase.AvailableMetrics.apply_filters(params)

    {:noreply,
     socket
     |> assign(
       visible_metrics: visible_metrics,
       filter: params
     )}
  end

  @doc ~s"""
  Checkbox that display description on hover.
  """
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
        class="flex flex-row flex-wrap space-y-2 items-start md:flex-row md:items-center md:gap-x-8"
      >
        <div>
          <.filter_input
            id="metric-name-search"
            value={@filter["match_metric_name"]}
            name="match_metric_name"
            placeholder="Filter by metric name"
          />

          <.filter_input
            id="table-search"
            value={@filter["match_table"]}
            name="match_metric_name"
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

  defp metric_access(assigns) do
    access_string =
      case assigns.access do
        %{"historical" => :free, "realtime" => :free} -> "FREE"
        _ -> "RESTRICTED"
      end

    assigns =
      assigns |> assign(:access_string, access_string)

    ~H"""
    <span><%= @access_string %></span>
    """
  end
end
