defmodule SanbaseWeb.CategoryLive.Index do
  use SanbaseWeb, :live_view

  import SanbaseWeb.CoreComponents
  alias Sanbase.Metric.UIMetadata.Category
  alias SanbaseWeb.AvailableMetricsComponents

  @impl true
  def mount(_params, _session, socket) do
    categories = Category.all_ordered()

    {:ok,
     socket
     |> assign(
       page_title: "Metric Categories",
       categories: categories,
       reordering: false
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col justify-center w-full">
      <div class="text-gray-800 text-2xl mb-4">
        Metric Categories
      </div>

      <.navigation />

      <.categories_table categories={@categories} />

      <.modal :if={@reordering} id="reordering-modal" show>
        <.header>Reordering Categories</.header>
        <div class="text-center py-4">
          <div class="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-500 mx-auto"></div>
          <p class="mt-4">Saving new order...</p>
        </div>
      </.modal>
    </div>
    """
  end

  attr :categories, :list, required: true

  def categories_table(assigns) do
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
              Category Name
            </th>
            <th
              scope="col"
              class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
            >
              Group Count
            </th>
            <th
              scope="col"
              class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
            >
              Actions
            </th>
          </tr>
        </thead>
        <tbody id="categories" phx-hook="Sortable" class="bg-white divide-y divide-gray-200">
          <.category_row
            :for={{category, index} <- Enum.with_index(@categories)}
            category={category}
            index={index}
            total_count={length(@categories)}
          />
        </tbody>
      </table>
    </div>
    """
  end

  attr :category, :map, required: true
  attr :index, :integer, required: true
  attr :total_count, :integer, required: true

  def category_row(assigns) do
    ~H"""
    <tr id={"category-#{@category.id}"} data-id={@category.id} class="hover:bg-gray-50">
      <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
        <div class="flex items-center">
          <button phx-click="move-up" phx-value-id={@category.id} class="mr-2" disabled={@index == 0}>
            <.icon name="hero-arrow-up" class="w-4 h-4" />
          </button>
          <span>{@category.display_order}</span>
          <button
            phx-click="move-down"
            phx-value-id={@category.id}
            class="ml-2"
            disabled={@index == @total_count - 1}
          >
            <.icon name="hero-arrow-down" class="w-4 h-4" />
          </button>
        </div>
      </td>
      <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
        {@category.name}
      </td>
      <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
        {length(Sanbase.Metric.UIMetadata.Group.by_category(@category.id))}
      </td>
      <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
        <.category_actions category={@category} />
      </td>
    </tr>
    """
  end

  attr :category, :map, required: true

  def category_actions(assigns) do
    ~H"""
    <div class="flex space-x-2">
      <.link
        navigate={~p"/admin/metric_registry/categories/edit/#{@category.id}"}
        class="text-blue-600 hover:text-blue-900"
      >
        Edit
      </.link>
      <button
        phx-click="delete"
        phx-value-id={@category.id}
        class="text-red-600 hover:text-red-900"
        data-confirm="Are you sure you want to delete this category? This will also delete all associated groups."
      >
        Delete
      </button>
    </div>
    """
  end

  def navigation(assigns) do
    ~H"""
    <div class="my-4 flex flex-row space-x-2">
      <AvailableMetricsComponents.available_metrics_button
        text="Back to Metric Registry"
        href={~p"/admin/metric_registry"}
        icon="hero-home"
      />
      <AvailableMetricsComponents.available_metrics_button
        text="Display Order"
        href={~p"/admin/metric_registry/display_order"}
        icon="hero-list-bullet"
      />
      <AvailableMetricsComponents.available_metrics_button
        text="Manage Groups"
        href={~p"/admin/metric_registry/groups"}
        icon="hero-user-group"
      />
      <AvailableMetricsComponents.link_button
        icon="hero-plus"
        text="Create New Category"
        href={~p"/admin/metric_registry/categories/new"}
      />
    </div>
    """
  end

  @impl true
  def handle_event("move-up", %{"id" => id}, socket) do
    id = String.to_integer(id)
    categories = socket.assigns.categories

    index = Enum.find_index(categories, &(&1.id == id))

    if index > 0 do
      current_category = Enum.at(categories, index)
      prev_category = Enum.at(categories, index - 1)

      # Swap display orders
      Category.update(current_category, %{display_order: prev_category.display_order})
      Category.update(prev_category, %{display_order: current_category.display_order})

      # Refresh categories
      categories = Category.all_ordered()

      {:noreply, assign(socket, categories: categories)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("move-down", %{"id" => id}, socket) do
    id = String.to_integer(id)
    categories = socket.assigns.categories

    index = Enum.find_index(categories, &(&1.id == id))

    if index < length(categories) - 1 do
      current_category = Enum.at(categories, index)
      next_category = Enum.at(categories, index + 1)

      # Swap display orders
      Category.update(current_category, %{display_order: next_category.display_order})
      Category.update(next_category, %{display_order: current_category.display_order})

      # Refresh categories
      categories = Category.all_ordered()

      {:noreply, assign(socket, categories: categories)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("reorder", %{"ids" => ids}, socket) do
    categories = socket.assigns.categories

    if length(categories) > 0 do
      # Update the display order for each category
      new_order =
        ids
        |> Enum.with_index(1)
        |> Enum.map(fn {id, index} ->
          # Extract the category id from the id (format: "category-{id}")
          category_id = id |> String.replace("category-", "") |> String.to_integer()
          %{id: category_id, display_order: index}
        end)

      # Save the new order
      socket = assign(socket, reordering: true)

      case Category.reorder(new_order) do
        {:ok, _} ->
          # Refresh the categories list
          categories = Category.all_ordered()

          {:noreply,
           socket
           |> assign(
             categories: categories,
             reordering: false
           )}

        {:error, reason} ->
          {:noreply,
           socket
           |> assign(reordering: false)
           |> put_flash(:error, "Failed to reorder categories: #{inspect(reason)}")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    id = String.to_integer(id)
    category = Category.by_id(id)

    if category do
      # First delete all groups associated with this category
      groups = Sanbase.Metric.UIMetadata.Group.by_category(id)
      Enum.each(groups, &Sanbase.Metric.UIMetadata.Group.delete/1)

      # Then delete the category
      Category.delete(category)

      # Refresh the categories list
      categories = Category.all_ordered()

      {:noreply,
       socket
       |> assign(categories: categories)
       |> put_flash(:info, "Category deleted successfully.")}
    else
      {:noreply,
       socket
       |> put_flash(:error, "Category not found.")}
    end
  end
end
