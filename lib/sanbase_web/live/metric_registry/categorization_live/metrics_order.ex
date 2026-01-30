defmodule SanbaseWeb.CategorizationLive.MetricsOrder do
  use SanbaseWeb, :live_view

  import SanbaseWeb.CoreComponents
  import SanbaseWeb.Categorization.ReorderComponents
  alias Sanbase.Metric.Category
  alias SanbaseWeb.AvailableMetricsComponents

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Reorder Metrics",
       category: nil,
       group: nil,
       mappings: [],
       reordering: false
     )}
  end

  @impl true
  def handle_params(params, _url, socket) do
    category_id = params["category_id"]
    group_id = params["group_id"]

    if is_nil(category_id) do
      {:noreply,
       socket
       |> put_flash(:error, "Category ID is required")
       |> push_navigate(to: ~p"/admin/metric_registry/categorization")}
    else
      load_category_and_metrics(socket, category_id, group_id)
    end
  end

  defp load_category_and_metrics(socket, category_id, group_id) do
    category_id = String.to_integer(category_id)

    case Category.get_category(category_id) do
      {:ok, category} ->
        {group, mappings} = load_group_and_mappings(category_id, group_id)

        page_title =
          if group do
            "Reorder Metrics - #{category.name} - #{group.name}"
          else
            "Reorder Ungrouped Metrics - #{category.name}"
          end

        {:noreply,
         socket
         |> assign(
           page_title: page_title,
           category: category,
           group: group,
           mappings: mappings
         )}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "Category not found")
         |> push_navigate(to: ~p"/admin/metric_registry/categorization")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col justify-center w-full">
      <div class="text-gray-800 text-2xl mb-4">
        <%= if @group do %>
          Reorder Metrics in Group: {@group.name}
        <% else %>
          Reorder Ungrouped Metrics
        <% end %>
      </div>

      <.breadcrumb_navigation category={@category} group={@group} />

      <%= if @mappings == [] do %>
        <.empty_state group={@group} />
      <% else %>
        <.metrics_table mappings={@mappings} />
      <% end %>

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

  attr :category, :map, required: true
  attr :group, :map, default: nil

  defp breadcrumb_navigation(assigns) do
    ~H"""
    <div class="my-4 flex flex-row space-x-2">
      <AvailableMetricsComponents.available_metrics_button
        text="Back to Categorization"
        href={~p"/admin/metric_registry/categorization"}
        icon="hero-arrow-left"
      />
      <AvailableMetricsComponents.available_metrics_button
        text="Back to Categories"
        href={~p"/admin/metric_registry/categorization/categories"}
        icon="hero-folder"
      />
      <AvailableMetricsComponents.available_metrics_button
        text="Back to Groups"
        href={~p"/admin/metric_registry/categorization/groups"}
        icon="hero-user-group"
      />
    </div>
    <div class="mb-4 text-sm text-gray-600">
      <span class="font-semibold">Category:</span>
      {@category.name}
      <%= if @group do %>
        <span class="mx-2">→</span>
        <span class="font-semibold">Group:</span>
        {@group.name}
      <% end %>
    </div>
    """
  end

  attr :group, :map, default: nil

  defp empty_state(assigns) do
    ~H"""
    <div class="bg-gray-50 border border-gray-200 rounded-lg p-8 text-center">
      <.icon name="hero-queue-list" class="w-16 h-16 mx-auto text-gray-400 mb-4" />
      <h3 class="text-lg font-medium text-gray-900 mb-2">
        No Metrics Found
      </h3>
      <p class="text-gray-500">
        <%= if @group do %>
          This group doesn't have any metrics assigned yet.
        <% else %>
          This category doesn't have any ungrouped metrics.
        <% end %>
      </p>
    </div>
    """
  end

  attr :mappings, :list, required: true

  defp metrics_table(assigns) do
    ~H"""
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
              Metric Name
            </th>
            <th
              scope="col"
              class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
            >
              Source
            </th>
          </tr>
        </thead>
        <tbody id="mappings" phx-hook="Sortable" class="bg-white divide-y divide-gray-200">
          <.mapping_row
            :for={{mapping, index} <- Enum.with_index(@mappings)}
            mapping={mapping}
            index={index}
            total_count={length(@mappings)}
          />
        </tbody>
      </table>
    </div>
    """
  end

  attr :mapping, :map, required: true
  attr :index, :integer, required: true
  attr :total_count, :integer, required: true

  defp mapping_row(assigns) do
    ~H"""
    <tr id={"mapping-#{@mapping.id}"} data-id={@mapping.id} class="hover:bg-gray-50">
      <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
        <.reorder_controls
          index={@index}
          total_count={@total_count}
          item_id={@mapping.id}
          display_order={@mapping.display_order || @index + 1}
        />
      </td>
      <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
        <.metric_name mapping={@mapping} />
      </td>
      <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
        <.metric_source mapping={@mapping} />
      </td>
    </tr>
    """
  end

  attr :mapping, :map, required: true

  defp metric_name(assigns) do
    ~H"""
    <%= if @mapping.metric_registry do %>
      {@mapping.metric_registry.metric}
    <% else %>
      {@mapping.metric}
    <% end %>
    """
  end

  attr :mapping, :map, required: true

  defp metric_source(assigns) do
    ~H"""
    <%= if @mapping.metric_registry_id do %>
      <span class="text-xs bg-blue-100 text-blue-800 px-2 py-1 rounded">
        Registry ID: {@mapping.metric_registry_id}
      </span>
    <% else %>
      <span class="text-xs bg-purple-100 text-purple-800 px-2 py-1 rounded">
        {@mapping.module}.{@mapping.metric}
      </span>
    <% end %>
    """
  end

  @impl true
  def handle_event("move-up", %{"id" => id}, socket) do
    id = String.to_integer(id)
    mappings = socket.assigns.mappings

    index = Enum.find_index(mappings, &(&1.id == id))

    if index > 0 do
      current_mapping = Enum.at(mappings, index)
      prev_mapping = Enum.at(mappings, index - 1)

      current_order = current_mapping.display_order || index + 1
      prev_order = prev_mapping.display_order || index

      {:ok, _} = Category.update_mapping(current_mapping, %{display_order: prev_order})
      {:ok, _} = Category.update_mapping(prev_mapping, %{display_order: current_order})

      mappings = reload_mappings(socket)

      {:noreply, assign(socket, mappings: mappings)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("move-down", %{"id" => id}, socket) do
    id = String.to_integer(id)
    mappings = socket.assigns.mappings

    index = Enum.find_index(mappings, &(&1.id == id))

    if index < length(mappings) - 1 do
      current_mapping = Enum.at(mappings, index)
      next_mapping = Enum.at(mappings, index + 1)

      current_order = current_mapping.display_order || index + 1
      next_order = next_mapping.display_order || index + 2

      {:ok, _} = Category.update_mapping(current_mapping, %{display_order: next_order})
      {:ok, _} = Category.update_mapping(next_mapping, %{display_order: current_order})

      mappings = reload_mappings(socket)

      {:noreply, assign(socket, mappings: mappings)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("reorder", %{"ids" => ids}, socket) do
    mappings = socket.assigns.mappings

    if mappings != [] do
      new_order = parse_reorder_ids(ids, "mapping")

      socket = assign(socket, reordering: true)

      case Category.reorder_mappings(new_order) do
        :ok ->
          mappings = reload_mappings(socket)

          {:noreply,
           socket
           |> assign(
             mappings: mappings,
             reordering: false
           )}

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

  defp load_group_and_mappings(category_id, nil) do
    mappings = Category.get_ungrouped_metrics(category_id)
    {nil, mappings}
  end

  defp load_group_and_mappings(category_id, group_id) when is_binary(group_id) do
    group_id = String.to_integer(group_id)

    case Category.get_group(group_id) do
      {:ok, group} ->
        mappings = Category.get_metrics_for_group(category_id, group_id)
        {group, mappings}

      {:error, _} ->
        {nil, []}
    end
  end

  defp reload_mappings(socket) do
    category_id = socket.assigns.category.id
    group = socket.assigns.group

    if group do
      Category.get_metrics_for_group(category_id, group.id)
    else
      Category.get_ungrouped_metrics(category_id)
    end
  end
end
