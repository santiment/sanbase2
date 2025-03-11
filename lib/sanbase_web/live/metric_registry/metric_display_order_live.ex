defmodule SanbaseWeb.MetricDisplayOrderLive do
  use SanbaseWeb, :live_view

  import SanbaseWeb.CoreComponents
  alias Sanbase.Metric.DisplayOrder
  alias SanbaseWeb.AvailableMetricsComponents

  @impl true
  def mount(_params, _session, socket) do
    ordered_data = DisplayOrder.get_ordered_metrics()
    metrics = ordered_data.metrics
    categories = ordered_data.categories

    {:ok,
     socket
     |> assign(
       page_title: "Metric Display Order",
       metrics: metrics,
       categories: categories,
       selected_category: List.first(categories),
       selected_group: nil,
       filtered_metrics: [],
       reordering: false
     )
     |> filter_metrics()}
  end

  @impl true
  def handle_params(params, _url, socket) do
    category = params["category"] || socket.assigns.selected_category
    group = params["group"]

    {:noreply,
     socket
     |> assign(selected_category: category, selected_group: group)
     |> filter_metrics()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col justify-center w-full">
      <div class="text-gray-800 text-2xl mb-4">
        Metric Display Order
      </div>

      <div class="my-4">
        <AvailableMetricsComponents.available_metrics_button
          text="Back to Metric Registry"
          href={~p"/admin2/metric_registry"}
          icon="hero-home"
        />
      </div>

      <div class="flex flex-row space-x-4 mb-4">
        <div class="w-1/4">
          <.simple_form for={%{}} as={:filter} phx-change="filter">
            <.input
              type="select"
              name="category"
              value={@selected_category}
              label="Category"
              options={@categories}
            />
          </.simple_form>
        </div>

        <div :if={@groups && length(@groups) > 0} class="w-1/4">
          <.simple_form for={%{}} as={:filter} phx-change="filter">
            <.input
              type="select"
              name="group"
              value={@selected_group}
              label="Group"
              options={[{"All Groups", nil} | @groups]}
            />
          </.simple_form>
        </div>
      </div>

      <div class="overflow-x-auto">
        <table class="min-w-full divide-y divide-gray-200">
          <thead class="bg-gray-50">
            <tr>
              <th
                scope="col"
                class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
              >
                Order
              </th>
              <th
                scope="col"
                class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
              >
                Metric
              </th>
              <th
                scope="col"
                class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
              >
                Label
              </th>
              <th
                scope="col"
                class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
              >
                Category
              </th>
              <th
                scope="col"
                class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
              >
                Group
              </th>
              <th
                scope="col"
                class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
              >
                Style
              </th>
              <th
                scope="col"
                class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
              >
                Format
              </th>
              <th
                scope="col"
                class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
              >
                Actions
              </th>
            </tr>
          </thead>
          <tbody id="metrics" phx-hook="Sortable" class="bg-white divide-y divide-gray-200">
            <%= for {metric, index} <- Enum.with_index(@filtered_metrics) do %>
              <tr id={"metric-#{metric.metric}"} data-id={metric.metric} class="hover:bg-gray-50">
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                  <div class="flex items-center">
                    <button
                      phx-click="move-up"
                      phx-value-metric={metric.metric}
                      class="mr-2"
                      disabled={index == 0}
                    >
                      <.icon name="hero-arrow-up" class="w-4 h-4" />
                    </button>
                    <span>{index + 1}</span>
                    <button
                      phx-click="move-down"
                      phx-value-metric={metric.metric}
                      class="ml-2"
                      disabled={index == length(@filtered_metrics) - 1}
                    >
                      <.icon name="hero-arrow-down" class="w-4 h-4" />
                    </button>
                  </div>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                  {metric.metric}
                  <%= if metric.is_new do %>
                    <span class="ml-2 px-2 inline-flex text-xs leading-5 font-semibold rounded-full bg-green-100 text-green-800">
                      NEW
                    </span>
                  <% end %>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                  {metric.label}
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                  {metric.category}
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                  {metric.group}
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                  {metric.style}
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                  {metric.format}
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                  <.metric_actions metric={metric} />
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>

      <.modal :if={@reordering} id="reordering-modal" show>
        <.header>Reordering Metrics</.header>
        <div class="text-center py-4">
          <div class="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-500 mx-auto"></div>
          <p class="mt-4">Saving new order...</p>
        </div>
      </.modal>
    </div>
    """
  end

  @impl true
  def handle_event("filter", %{"category" => category}, socket) do
    {:noreply,
     socket
     |> assign(selected_category: category, selected_group: nil)
     |> push_patch(to: ~p"/admin2/metric_registry/display_order?category=#{category}")}
  end

  def handle_event("filter", %{"group" => group}, socket) do
    {:noreply,
     socket
     |> assign(selected_group: group)
     |> push_patch(
       to:
         ~p"/admin2/metric_registry/display_order?category=#{socket.assigns.selected_category}&group=#{group}"
     )}
  end

  def handle_event("move-up", %{"metric" => metric}, socket) do
    metrics = socket.assigns.filtered_metrics
    index = Enum.find_index(metrics, &(&1.metric == metric))

    if index > 0 do
      # Swap with the previous metric
      metrics =
        List.update_at(metrics, index - 1, fn prev_metric ->
          display_order = DisplayOrder.by_metric(prev_metric.metric)
          DisplayOrder.update(display_order, %{display_order: display_order.display_order + 1})
          %{prev_metric | display_order: display_order.display_order + 1}
        end)

      metrics =
        List.update_at(metrics, index, fn current_metric ->
          display_order = DisplayOrder.by_metric(current_metric.metric)
          DisplayOrder.update(display_order, %{display_order: display_order.display_order - 1})
          %{current_metric | display_order: display_order.display_order - 1}
        end)

      # Sort by display_order
      metrics = Enum.sort_by(metrics, & &1.display_order)

      {:noreply, assign(socket, filtered_metrics: metrics)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("move-down", %{"metric" => metric}, socket) do
    metrics = socket.assigns.filtered_metrics
    index = Enum.find_index(metrics, &(&1.metric == metric))

    if index < length(metrics) - 1 do
      # Swap with the next metric
      metrics =
        List.update_at(metrics, index + 1, fn next_metric ->
          display_order = DisplayOrder.by_metric(next_metric.metric)
          DisplayOrder.update(display_order, %{display_order: display_order.display_order - 1})
          %{next_metric | display_order: display_order.display_order - 1}
        end)

      metrics =
        List.update_at(metrics, index, fn current_metric ->
          display_order = DisplayOrder.by_metric(current_metric.metric)
          DisplayOrder.update(display_order, %{display_order: display_order.display_order + 1})
          %{current_metric | display_order: display_order.display_order + 1}
        end)

      # Sort by display_order
      metrics = Enum.sort_by(metrics, & &1.display_order)

      {:noreply, assign(socket, filtered_metrics: metrics)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("reorder", %{"ids" => ids}, socket) do
    metrics = socket.assigns.filtered_metrics

    if length(metrics) > 0 do
      first_metric = List.first(metrics)
      category = first_metric.category

      # Update the display order for each metric
      new_order =
        ids
        |> Enum.with_index(1)
        |> Enum.map(fn {id, index} ->
          # Extract the metric name from the id (format: "metric-{metric_name}")
          metric = String.replace(id, "metric-", "")
          %{metric: metric, display_order: index}
        end)

      # Save the new order
      socket = assign(socket, reordering: true)

      case DisplayOrder.reorder_metrics(category, new_order) do
        {:ok, _} ->
          # Refresh the metrics list
          ordered_data = DisplayOrder.get_ordered_metrics()
          metrics = ordered_data.metrics

          {:noreply,
           socket
           |> assign(
             metrics: metrics,
             reordering: false
           )
           |> filter_metrics()}

        {:error, reason} ->
          {:noreply,
           socket
           |> assign(reordering: false)
           |> put_flash(:error, "Failed to reorder metrics: #{inspect(reason)}")}
      end
    else
      {:noreply, socket}
    end
  end

  defp filter_metrics(socket) do
    %{metrics: metrics, selected_category: category, selected_group: group} = socket.assigns

    # Filter metrics by category
    filtered_metrics =
      metrics
      |> Enum.filter(&(&1.category == category))

    # Get unique groups for this category
    groups =
      filtered_metrics
      |> Enum.map(& &1.group)
      |> Enum.uniq()
      |> Enum.sort()

    # Filter by group if selected
    filtered_metrics =
      if group && group != "" do
        Enum.filter(filtered_metrics, &(&1.group == group))
      else
        filtered_metrics
      end

    # Sort by display_order
    filtered_metrics = Enum.sort_by(filtered_metrics, & &1.display_order)

    assign(socket, filtered_metrics: filtered_metrics, groups: groups)
  end

  attr :metric, :map, required: true

  def metric_actions(assigns) do
    ~H"""
    <div class="flex space-x-2">
      <.link
        :if={@metric.source_type == "registry"}
        navigate={~p"/admin2/metric_registry/show/#{@metric.source_id}"}
        class="text-blue-600 hover:text-blue-900"
      >
        Show
      </.link>
      <.link
        :if={@metric.source_type == "registry"}
        navigate={~p"/admin2/metric_registry/edit/#{@metric.source_id}"}
        class="text-green-600 hover:text-green-900"
      >
        Edit
      </.link>
      <.link
        :if={@metric.source_type != "registry"}
        navigate={~p"/admin2/metric_registry/display_order/show/#{@metric.metric}"}
        class="text-blue-600 hover:text-blue-900"
      >
        Show
      </.link>
      <.link
        :if={@metric.source_type == "code"}
        navigate={~p"/admin2/metric_registry/display_order/edit/#{@metric.metric}"}
        class="text-green-600 hover:text-green-900"
      >
        Edit
      </.link>
    </div>
    """
  end
end
