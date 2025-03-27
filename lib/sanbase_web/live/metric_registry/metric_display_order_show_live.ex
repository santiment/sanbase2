defmodule SanbaseWeb.MetricDisplayOrderShowLive do
  use SanbaseWeb, :live_view

  import SanbaseWeb.CoreComponents
  alias Sanbase.Metric.UIMetadata.DisplayOrder
  alias SanbaseWeb.AvailableMetricsComponents

  @impl true
  def mount(%{"metric_id" => metric_id}, _session, socket) do
    case DisplayOrder.by_id(String.to_integer(metric_id)) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Metric not found")
         |> push_navigate(to: ~p"/admin/metric_registry/display_order")}

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
        href={~p"/admin/metric_registry/display_order"}
        icon="hero-arrow-uturn-left"
      />

      <AvailableMetricsComponents.available_metrics_button
        text="Edit Metric"
        href={~p"/admin/metric_registry/display_order/edit/#{@display_order.id}"}
        icon="hero-pencil-square"
      />
    </div>
    """
  end

  attr :display_order, :map, required: true

  def metric_details(assigns) do
    category_name =
      if assigns.display_order.category,
        do: assigns.display_order.category.name,
        else: ""

    group_name =
      if assigns.display_order.group,
        do: assigns.display_order.group.name,
        else: ""

    added_at =
      case assigns.display_order.inserted_at do
        nil ->
          "Not specified"

        date when is_struct(date, NaiveDateTime) ->
          Calendar.strftime(date, "%Y-%m-%d %H:%M:%S")

        date when is_struct(date, DateTime) ->
          Calendar.strftime(date, "%Y-%m-%d %H:%M:%S")

        _ ->
          "Invalid date format"
      end

    rows = [
      %{key: "Metric", value: assigns.display_order.metric},
      %{key: "Label", value: assigns.display_order.ui_human_readable_name || ""},
      %{key: "UI Key", value: assigns.display_order.ui_key || ""},
      %{key: "Category", value: category_name},
      %{key: "Group", value: group_name},
      %{key: "Display Order", value: assigns.display_order.display_order},
      %{key: "Code Module", value: assigns.display_order.code_module || "None"},
      %{key: "Metric Registry ID", value: assigns.display_order.metric_registry_id},
      %{key: "Added At", value: added_at},
      %{key: "Chart Style", value: assigns.display_order.chart_style || "line"},
      %{key: "Unit", value: assigns.display_order.unit || ""},
      %{key: "Description", value: assigns.display_order.description || ""},
      %{key: "Args", value: inspect(assigns.display_order.args || %{})}
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
