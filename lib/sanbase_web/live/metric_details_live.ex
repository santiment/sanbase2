defmodule SanbaseWeb.MetricDetailsLive do
  use SanbaseWeb, :live_view

  @impl true
  def mount(%{"metric" => metric}, _session, socket) do
    {:ok, metadata} = Sanbase.Metric.metadata(metric)
    {:ok, slugs} = Sanbase.AvailableMetrics.get_metric_available_slugs(metric)
    transform_aggr = fn aggr -> aggr |> to_string() |> String.upcase() end

    rows = [
      %{key: "Name", value: metric},
      %{key: "Internal Name", value: metadata.internal_metric},
      %{key: "Frequency", value: metadata.min_interval},
      %{key: "Docs", value: metadata.docs || []},
      %{key: "Has Incomplete Data", value: metadata.has_incomplete_data},
      %{key: "Default Aggregation", value: transform_aggr.(metadata.default_aggregation)},
      %{key: "Is Timebound", value: metadata.is_timebound},
      %{
        key: "Available Aggregations",
        value: Enum.map(metadata.available_aggregations, transform_aggr) |> Enum.join(", ")
      },
      %{key: "Complexity Weight", value: metadata.complexity_weight},
      %{key: "Data Type", value: metadata.data_type},
      %{key: "Available Slugs", value: slugs}
    ]

    {:ok,
     socket
     |> assign(
       metric: metric,
       metadata: metadata,
       rows: rows
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col justify-center w-7/8">
      <div class="text-gray-800 text-lg">
        Showing details for <%= @metric %>
      </div>
      <.table id="available_metrics" rows={@rows}>
        <:col :let={row}>
          <%= row.key %>
        </:col>
        <:col :let={row}>
          <.formatted_value key={row.key} value={row.value} />
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

  defp formatted_value(%{key: "Available Slugs"} = assigns) do
    str = assigns.value |> Enum.join(", ")

    assigns = assigns |> assign(available_slugs: str)

    ~H"""
    <div class="w-1/2">
      <%= @available_slugs %>
    </div>
    """
  end

  defp formatted_value(%{key: "Docs"} = assigns) do
    assigns |> dbg()

    ~H"""
    <div class="flex flex-row">
      <a :for={doc <- assigns.value} href={doc.link} target="_blank">
        Open Docs
      </a>
    </div>
    """
  end

  defp formatted_value(assigns) do
    ~H"""
    <div>
      <%= to_string(@value) %>
    </div>
    """
  end

  defp available_assets(assigns) do
    {first_2, rest} = Enum.split(assigns.assets, 200)
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
end
