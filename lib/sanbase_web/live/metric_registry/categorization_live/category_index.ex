defmodule SanbaseWeb.Categorization.CategoryLive.Index do
  use SanbaseWeb, :live_view

  import SanbaseWeb.Categorization.ReorderComponents
  alias Sanbase.Metric.Category
  alias SanbaseWeb.AdminSharedComponents

  @impl true
  def mount(_params, _session, socket) do
    categories = Category.list_categories_with_groups()

    {:ok,
     socket
     |> assign(
       page_title: "Metric Categorization",
       categories: categories,
       reordering: false
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col justify-center w-full">
      <div class="text-2xl mb-4">
        Metric Categories
      </div>

      <.navigation />

      <.categories_table categories={@categories} />

      <.modal :if={@reordering} id="reordering-modal" show>
        <.header>Reordering Categories</.header>
        <div class="text-center py-4">
          <span class="loading loading-spinner loading-lg text-primary"></span>
          <p class="mt-4">Saving new order...</p>
        </div>
      </.modal>
    </div>
    """
  end

  attr :categories, :list, required: true

  def categories_table(assigns) do
    ~H"""
    <div class="rounded-box border border-base-300 overflow-x-auto">
      <table class="table table-zebra table-sm">
        <thead>
          <tr>
            <th>Order</th>
            <th>Category Name</th>
            <th>Groups Count</th>
            <th>Actions</th>
          </tr>
        </thead>
        <tbody id="categories" phx-hook="Sortable">
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
    <tr id={"category-#{@category.id}"} data-id={@category.id}>
      <td>
        <.reorder_controls
          index={@index}
          total_count={@total_count}
          item_id={@category.id}
          display_order={@category.display_order}
        />
      </td>
      <td>{@category.name}</td>
      <td>{length(@category.groups)}</td>
      <td>
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
        navigate={~p"/admin/metric_registry/categorization/categories/edit/#{@category.id}"}
        class="link link-primary"
      >
        Edit
      </.link>
      <button
        phx-click="delete"
        phx-value-id={@category.id}
        class="link link-error"
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
      <AdminSharedComponents.nav_button
        text="Back to Categorization"
        href={~p"/admin/metric_registry/categorization"}
        icon="hero-arrow-left"
      />
      <AdminSharedComponents.nav_button
        text="Manage Groups"
        href={~p"/admin/metric_registry/categorization/groups"}
        icon="hero-user-group"
      />
      <AdminSharedComponents.nav_button
        icon="hero-plus"
        text="Create New Category"
        href={~p"/admin/metric_registry/categorization/categories/new"}
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

      {:ok, _} = Category.swap_categories_display_orders(current_category, prev_category)

      # Refresh categories
      categories = Category.list_categories_with_groups()

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

      {:ok, _} = Category.swap_categories_display_orders(current_category, next_category)

      # Refresh categories
      categories = Category.all_ordered()

      {:noreply, assign(socket, categories: categories)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("reorder", %{"ids" => ids}, socket) do
    categories = socket.assigns.categories

    if categories != [] do
      new_order = parse_reorder_ids(ids, "category")

      socket = assign(socket, reordering: true)

      case Category.reorder_categories(new_order) do
        :ok ->
          categories = Category.list_categories_with_groups()

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

    case Category.get_category(id) do
      {:ok, category} ->
        groups = Category.list_groups_by_category(id)
        Enum.each(groups, &Category.delete_group/1)

        {:ok, _} = Category.delete_category(category)

        categories = Category.list_categories_with_groups()

        {:noreply,
         socket
         |> assign(categories: categories)
         |> put_flash(:info, "Category deleted successfully.")}

      _ ->
        {:noreply,
         socket
         |> put_flash(:error, "Category not found.")}
    end
  end
end
