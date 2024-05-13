defmodule SanbaseWeb.MetricDetailsLive do
  use SanbaseWeb, :live_view

  @impl true
  def mount(%{"metric" => metric}, _session, socket) do
    rows = get_rows(metric)

    {:ok,
     socket
     |> assign(
       metric: metric,
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
        <:col :let={row} col_class="min-w-[200px]">
          <div class="relative">
            <div data-popover-target={Map.get(row, :popover_target)} data-popover-style="light">
              <span class="border-b border-dotted border-gray-500 hover:cursor-pointer">
                <%= row.key %>
              </span>
            </div>

            <div
              id={Map.get(row, :popover_target)}
              role="tooltip"
              class="absolute top-0 right-10 z-10 invisible inline-block px-8 py-6 text-sm font-medium text-gray-600 bg-white border border-gray-200 rounded-lg shadow-sm opacity-0 popover"
            >
              <span><%= Map.get(row, :popover_target_text) %></span>
              <div class="popover-arrow" data-popper-arrow></div>
            </div>
          </div>
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
    last_slug = Enum.at(assigns.value, -1)
    assigns = assign(assigns, :last_slug, last_slug)

    ~H"""
    <div class="w-3/4">
      <a :for={slug <- @value} href={SanbaseWeb.Endpoint.project_url(slug)}>
        <!-- Keep the template and span glued, otherwise there will be a white space -->
        <%= slug %><span :if={slug != @last_slug}>,</span>
      </a>
    </div>
    """
  end

  defp formatted_value(%{key: "Docs"} = assigns) do
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

  defp get_rows(metric) do
    {:ok, metadata} = Sanbase.Metric.metadata(metric)
    {:ok, slugs} = Sanbase.AvailableMetrics.get_metric_available_slugs(metric)

    transform_atom = fn atom when is_atom(atom) -> atom |> to_string() |> String.upcase() end
    transform_atoms = fn atoms -> Enum.map(atoms, transform_atom) |> Enum.join(", ") end

    rows = [
      %{
        key: "Name",
        value: metric,
        popover_target: "popover-name",
        popover_target_text: get_popover_text(%{key: "Name"})
      },
      %{
        key: "Internal Name",
        value: metadata.internal_metric,
        popover_target: "popover-internal-name",
        popover_target_text: get_popover_text(%{key: "Internal Name"})
      },
      %{
        key: "Frequency",
        value: metadata.min_interval,
        popover_target: "popover-frequency",
        popover_target_text: get_popover_text(%{key: "Frequency"})
      },
      %{
        key: "Docs",
        value: metadata.docs || [],
        popover_target: "popover-docs",
        popover_target_text: get_popover_text(%{key: "Docs"})
      },
      %{
        key: "Has Incomplete Data",
        value: metadata.has_incomplete_data,
        popover_target: "popover-incomplete-data",
        popover_target_text: get_popover_text(%{key: "Has Incomplete Data"})
      },
      %{key: "Default Aggregation", value: transform_atom.(metadata.default_aggregation)},
      %{key: "Is Timebound", value: metadata.is_timebound},
      %{key: "Available Aggregations", value: transform_atoms.(metadata.available_aggregations)},
      %{key: "Available Selectors", value: transform_atoms.(metadata.available_selectors)},
      %{key: "Required Selectors", value: transform_atoms.(metadata.required_selectors)},
      %{key: "Complexity Weight", value: metadata.complexity_weight},
      %{key: "Data Type", value: metadata.data_type},
      %{key: "Available Slugs", value: slugs}
    ]

    # If there are no required selectors, do not include this row
    rows =
      if metadata.required_selectors == [],
        do: Enum.reject(rows, &(&1.key == "Required Selectors")),
        else: rows

    rows
  end

  defp get_popover_text(%{key: "Name"} = assigns) do
    ~H"""
    <pre>
    The name of the metric that is used in the public API.
    For example, if the metric is `price_usd` it is provided as the `metric` argument.

    Example:

      {
        getMetric(metric: "price_usd"){
          timeseriesData(slug: "ethereum" from: "utc_now-90d" to: "utc_now" interval: "1d"){
            datetime
            value
          }
        }
      }
    </pre>
    """
  end

  defp get_popover_text(%{key: "Internal Name"} = assigns) do
    ~H"""
    <pre>
    The name of the metric that is used in the database tables.
    The database tables are accessed through Santiment Queries when the
    user interacts with the data via SQL.

    How to use Santiment Queries, check <.link href="https://academy.santiment.net/santiment-queries" class="underline text-blue-600">this link</.link>
    </pre>
    """
  end

  defp get_popover_text(%{key: "Frequency"} = assigns) do
    ~H"""
    <pre>
    The minimum interval at which the metric is updated.
    </pre>
    """
  end

  defp get_popover_text(%{key: "Docs"} = assigns) do
    ~H"""
    <pre>
    The link to the documentation page for the metric.
    </pre>
    """
  end

  defp get_popover_text(%{key: "Has Incomplete Data"} = assigns) do
    ~H"""
    <pre>
    A boolean that indicates whether the metric has incomplete data.
    </pre>
    """
  end
end
