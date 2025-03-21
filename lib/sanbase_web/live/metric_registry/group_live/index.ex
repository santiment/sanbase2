defmodule SanbaseWeb.GroupLive.Index do
  use SanbaseWeb, :live_view

  import SanbaseWeb.CoreComponents
  alias Sanbase.Metric.UIMetadata.Category
  alias Sanbase.Metric.UIMetadata.Group
  alias SanbaseWeb.AvailableMetricsComponents

  @impl true
  def mount(_params, _session, socket) do
    # Get all categories with their groups
    categories_with_groups = Category.with_groups()

    {:ok,
     socket
     |> assign(
       page_title: "Metric Groups",
       categories_with_groups: categories_with_groups,
       selected_category_id: nil
     )}
  end

  @impl true
  def handle_params(params, _url, socket) do
    selected_category_id =
      if params["category_id"] do
        String.to_integer(params["category_id"])
      else
        nil
      end

    {:noreply,
     socket
     |> assign(selected_category_id: selected_category_id)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col justify-center w-full">
      <div class="text-gray-800 text-2xl mb-4">
        Metric Groups
      </div>

      <.navigation />

      <.category_filter
        categories_with_groups={@categories_with_groups}
        selected_category_id={@selected_category_id}
      />

      <.groups_table categories={filter_categories(@categories_with_groups, @selected_category_id)} />
    </div>
    """
  end

  attr :categories_with_groups, :list, required: true
  attr :selected_category_id, :any, required: true

  def category_filter(assigns) do
    ~H"""
    <div class="mb-4">
      <.simple_form for={%{}} as={:filter} phx-change="filter">
        <.input
          type="select"
          name="category_id"
          value={@selected_category_id}
          label="Filter by Category"
          options={[
            {"All Categories", ""}
            | Enum.map(@categories_with_groups, fn cat -> {cat.name, cat.id} end)
          ]}
        />
      </.simple_form>
    </div>
    """
  end

  attr :categories, :list, required: true

  def groups_table(assigns) do
    ~H"""
    <div class="overflow-x-auto">
      <table class="min-w-full divide-y divide-gray-200">
        <thead class="bg-gray-50">
          <tr>
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
              Group Name
            </th>
            <th
              scope="col"
              class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
            >
              Actions
            </th>
          </tr>
        </thead>
        <tbody class="bg-white divide-y divide-gray-200">
          <.category_groups :for={category <- @categories} category={category} />
        </tbody>
      </table>
    </div>
    """
  end

  attr :category, :map, required: true

  def category_groups(assigns) do
    ~H"""
    <.group_row
      :for={{group, index} <- Enum.with_index(@category.groups)}
      group={group}
      category={@category}
      index={index}
      category_groups_count={length(@category.groups)}
    />
    <.empty_category_row :if={Enum.empty?(@category.groups)} category={@category} />
    """
  end

  attr :group, :map, required: true
  attr :category, :map, required: true
  attr :index, :integer, required: true
  attr :category_groups_count, :integer, required: true

  def group_row(assigns) do
    ~H"""
    <tr class="hover:bg-gray-50">
      <td
        :if={@index == 0}
        class="px-6 py-4 whitespace-nowrap text-sm text-gray-500"
        rowspan={@category_groups_count}
      >
        {@category.name}
      </td>
      <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
        {@group.name}
      </td>
      <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
        <.group_actions group={@group} />
      </td>
    </tr>
    """
  end

  attr :category, :map, required: true

  def empty_category_row(assigns) do
    ~H"""
    <tr class="hover:bg-gray-50">
      <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
        {@category.name}
      </td>
      <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500 italic">
        No groups
      </td>
      <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
        <.link
          navigate={~p"/admin/metric_registry/groups/new?category_id=#{@category.id}"}
          class="text-blue-600 hover:text-blue-900"
        >
          Add Group
        </.link>
      </td>
    </tr>
    """
  end

  attr :group, :map, required: true

  def group_actions(assigns) do
    ~H"""
    <div class="flex space-x-2">
      <.link
        navigate={~p"/admin/metric_registry/groups/edit/#{@group.id}"}
        class="text-blue-600 hover:text-blue-900"
      >
        Edit
      </.link>
      <button
        phx-click="delete"
        phx-value-id={@group.id}
        class="text-red-600 hover:text-red-900"
        data-confirm="Are you sure you want to delete this group?"
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
        text="Manage Categories"
        href={~p"/admin/metric_registry/categories"}
        icon="hero-rectangle-group"
      />
      <AvailableMetricsComponents.link_button
        icon="hero-plus"
        text="Create New Group"
        href={~p"/admin/metric_registry/groups/new"}
      />
    </div>
    """
  end

  @impl true
  def handle_event("filter", %{"category_id" => category_id}, socket) do
    category_id = if category_id == "", do: nil, else: String.to_integer(category_id)

    {:noreply,
     socket
     |> push_patch(to: ~p"/admin/metric_registry/groups?category_id=#{category_id || ""}")}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    id = String.to_integer(id)
    group = Group.by_id(id)

    if group do
      Group.delete(group)

      # Refresh the categories with groups
      categories_with_groups = Category.with_groups()

      {:noreply,
       socket
       |> assign(categories_with_groups: categories_with_groups)
       |> put_flash(:info, "Group deleted successfully.")}
    else
      {:noreply,
       socket
       |> put_flash(:error, "Group not found.")}
    end
  end

  # Filter categories based on selected category_id
  defp filter_categories(categories, nil), do: categories

  defp filter_categories(categories, category_id) do
    Enum.filter(categories, &(&1.id == category_id))
  end
end
