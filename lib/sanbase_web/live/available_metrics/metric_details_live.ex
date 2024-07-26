defmodule SanbaseWeb.MetricDetailsLive do
  use SanbaseWeb, :live_view

  import SanbaseWeb.CoreComponents
  import SanbaseWeb.AvailableMetricsDescription

  alias SanbaseWeb.AvailableMetricsComponents

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
      <h1 class="text-gray-800 text-2xl">
        Showing details for <span class="text-blue-700"><%= @metric %></span>
      </h1>
      <div class="my-4">
        <AvailableMetricsComponents.available_metrics_button
          text="Back to Available Metrics"
          href={~p"/available_metrics"}
          icon="hero-arrow-uturn-left"
        />
      </div>
      <.table id="available_metrics" rows={@rows}>
        <:col :let={row} col_class="w-40">
          <AvailableMetricsComponents.popover
            display_text={row.key}
            popover_target={Map.get(row, :popover_target)}
            popover_target_text={Map.get(row, :popover_target_text)}
          />
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

  defp formatted_value(%{key: "Available Assets"} = assigns) do
    last_asset = Enum.at(assigns.value, -1)
    assigns = assign(assigns, :last_asset, last_asset)

    ~H"""
    <div class="w-3/4">
      <a :for={asset <- @value} href={SanbaseWeb.Endpoint.project_url(asset)}>
        <!-- Keep the template and span glued, otherwise there will be a white space -->
        <%= asset %><span :if={asset != @last_asset}>,</span>
      </a>
    </div>
    """
  end

  defp formatted_value(%{key: "Docs"} = assigns) do
    ~H"""
    <div class="flex flex-row">
      <AvailableMetricsComponents.available_metrics_button
        :for={doc <- assigns.value}
        href={doc.link}
        text="Docs"
        icon="hero-clipboard-document-list"
      />
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

  defp stringify(ll) do
    ll
    |> List.wrap()
    |> Enum.map(fn x -> x |> to_string() |> String.upcase() end)
    |> Enum.join(", ")
  end

  defp stringify_required_selectors(l) when is_list(l) do
    Enum.map(l, fn
      ll when is_list(ll) ->
        str = Enum.map(ll, fn x -> x |> to_string() |> String.upcase() end) |> Enum.join(" or ")
        if length(ll) > 1, do: "(#{str})", else: str

      x ->
        x |> to_string() |> String.upcase()
    end)
    |> Enum.join(" and ")
  end

  defp get_rows(metric) do
    {:ok, metadata} = Sanbase.Metric.metadata(metric)
    {:ok, assets} = Sanbase.AvailableMetrics.get_metric_available_slugs(metric)
    access_map = Sanbase.Metric.access_map()

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
      %{
        key: "Default Aggregation",
        value: stringify(metadata.default_aggregation),
        popover_target: "popover-default-aggregation",
        popover_target_text: get_popover_text(%{key: "Default Aggregation"})
      },
      %{
        key: "Access",
        value: simplify_access(Map.get(access_map, metric)),
        popover_target: "popover-access",
        popover_target_text: get_popover_text(%{key: "Access"})
      },
      %{
        key: "Is Timebound",
        value: metadata.is_timebound,
        popover_target: "popover-timebound",
        popover_target_text: get_popover_text(%{key: "Is Timebound"})
      },
      %{
        key: "Available Aggregations",
        value: stringify(metadata.available_aggregations),
        popover_target: "popover-available-aggregations",
        popover_target_text: get_popover_text(%{key: "Available Aggregations"})
      },
      %{
        key: "Available Selectors",
        value: stringify(metadata.available_selectors),
        popover_target: "popover-available-selectors",
        popover_target_text: get_popover_text(%{key: "Available Selectors"})
      },
      %{
        key: "Required Selectors",
        value: stringify_required_selectors(metadata.required_selectors),
        popover_target: "popover-required-selectors",
        popover_target_text: get_popover_text(%{key: "Required Selectors"})
      },
      %{
        key: "Data Type",
        value: metadata.data_type,
        popover_target: "popover-data-type",
        popover_target_text: get_popover_text(%{key: "Data Type"})
      },
      %{
        key: "Available Assets",
        value: assets,
        popover_target: "popover-available-assets",
        popover_target_text: get_popover_text(%{key: "Available Assets"})
      }
    ]

    # If there are no required selectors, do not include this row
    rows =
      if metadata.required_selectors == [],
        do: Enum.reject(rows, &(&1.key == "Required Selectors")),
        else: rows

    rows
  end

  defp simplify_access(%{"historical" => :free, "realtime" => :free}), do: "FREE"

  defp simplify_access(%{"historical" => :restricted, "realtime" => :restricted}),
    do: "RESTRICTED"
end
