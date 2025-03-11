defmodule SanbaseWeb.MetricDisplayOrderShowLive do
  use SanbaseWeb, :live_view

  import SanbaseWeb.CoreComponents
  alias Sanbase.Metric.DisplayOrder
  alias SanbaseWeb.AvailableMetricsComponents

  @impl true
  def mount(%{"metric" => metric}, _session, socket) do
    case DisplayOrder.by_metric(metric) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Metric not found")
         |> push_navigate(to: ~p"/admin2/metric_registry/display_order")}

      display_order ->
        {:ok,
         socket
         |> assign(
           page_title: "Metric Display Order | #{display_order.metric}",
           display_order: display_order
         )}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col justify-center w-full">
      <h1 class="text-blue-700 text-2xl mb-4">
        Metric Display Order Details | {@display_order.metric}
      </h1>

      <.action_buttons display_order={@display_order} />
      <.metric_details display_order={@display_order} />
    </div>
    """
  end

  attr :display_order, :map, required: true

  def action_buttons(assigns) do
    ~H"""
    <div class="my-4">
      <AvailableMetricsComponents.available_metrics_button
        text="Back to Display Order"
        href={~p"/admin2/metric_registry/display_order"}
        icon="hero-arrow-uturn-left"
      />

      <AvailableMetricsComponents.available_metrics_button
        :if={@display_order.source_type == "code"}
        text="Edit Metric"
        href={~p"/admin2/metric_registry/display_order/edit/#{@display_order.metric}"}
        icon="hero-pencil-square"
      />
    </div>
    """
  end

  attr :display_order, :map, required: true

  def metric_details(assigns) do
    rows = [
      %{key: "Metric", value: assigns.display_order.metric},
      %{key: "Label", value: assigns.display_order.label || ""},
      %{key: "Category", value: assigns.display_order.category},
      %{key: "Group", value: assigns.display_order.group || ""},
      %{key: "Display Order", value: assigns.display_order.display_order},
      %{key: "Source Type", value: assigns.display_order.source_type},
      %{key: "Source ID", value: assigns.display_order.source_id},
      %{key: "Added At", value: assigns.display_order.added_at || "Not specified"},
      %{key: "Style", value: assigns.display_order.style || "line"},
      %{key: "Format", value: assigns.display_order.format || ""},
      %{key: "Description", value: assigns.display_order.description || ""}
    ]

    assigns = assign(assigns, :rows, rows)

    ~H"""
    <.table id="display_order" rows={@rows}>
      <:col :let={row} col_class="w-40">
        {row.key}
      </:col>

      <:col :let={row}>
        {row.value}
      </:col>
    </.table>
    """
  end
end
