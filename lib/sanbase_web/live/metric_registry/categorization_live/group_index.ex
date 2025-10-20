defmodule SanbaseWeb.Categorization.GroupLive.Index do
  use SanbaseWeb, :live_view

  import SanbaseWeb.CoreComponents
  import SanbaseWeb.Categorization.ReorderComponents
  alias Sanbase.Metric.Category
  alias SanbaseWeb.AvailableMetricsComponents

  @impl true
  def mount(_params, _session, socket) do
    # Get all categories with their groups
    categories_with_groups = Category.list_categories_with_groups()

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
    category_id =
      if params["category_id"] in [nil, ""],
        do: nil,
        else: String.to_integer(params["category_id"])

    {:noreply, socket |> assign(selected_category_id: category_id)}
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
            | Enum.map(@categories_with_groups, fn c -> {c.name, c.id} end)
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
      <div :for={category <- @categories} class="mb-8">
        <div
          :if={!Enum.empty?(category.groups)}
          class="bg-gray-100 px-4 py-2 font-semibold text-gray-700"
        >
          {category.name}
        </div>
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
                Group Name
              </th>
              <th
                scope="col"
                class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
              >
                Metrics Count
              </th>
              <th
                scope="col"
                class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
              >
                Actions
              </th>
            </tr>
          </thead>
          <tbody
            :if={!Enum.empty?(category.groups)}
            id={"groups-category-#{category.id}"}
            phx-hook="Sortable"
            class="bg-white divide-y divide-gray-200"
          >
            <.group_row
              :for={{group, index} <- Enum.with_index(category.groups)}
              group={group}
              category={category}
              index={index}
              category_groups_count={length(category.groups)}
            />
          </tbody>
        </table>
        <.empty_category_row :if={Enum.empty?(category.groups)} category={category} />

        <div class="flex flex-col md:flex-row space-y-2 md:space-y-0 md:space-x-4 mt-4">
          <.add_group_button category_id={category.id} />
          <.button_reorder_ungrouped_metrics category={category} />
        </div>
      </div>
    </div>
    """
  end

  attr :group, :map, required: true
  attr :category, :map, required: true
  attr :index, :integer, required: true
  attr :category_groups_count, :integer, required: true

  def group_row(assigns) do
    ~H"""
    <tr id={"group-#{@group.id}"} data-id={@group.id} class="hover:bg-gray-50">
      <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
        <.reorder_controls
          index={@index}
          total_count={@category_groups_count}
          item_id={@group.id}
          display_order={@group.display_order}
          event_prefix="group-"
        />
      </td>
      <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
        {@group.name}
      </td>

      <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
        {length(@group.mappings)}
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
    <div class="bg-white p-6 text-center border border-gray-200 rounded">
      <p class="text-gray-500 italic mb-2">No groups in {@category.name}</p>
    </div>
    """
  end

  def add_group_button(assigns) do
    ~H"""
    <div>
      <AvailableMetricsComponents.link_button
        href={~p"/admin/metric_registry/categorization/groups/new?category_id=#{@category_id}"}
        text="Add Group"
        icon="hero-plus"
      />
    </div>
    """
  end

  attr :category, :map, required: true

  def button_reorder_ungrouped_metrics(assigns) do
    ungrouped_metrics_count =
      assigns.category.mappings
      |> Enum.filter(&is_nil(&1.group_id))
      |> length()

    assigns = assign(assigns, ungrouped_metrics_count: ungrouped_metrics_count)

    ~H"""
    <div class="mt-4">
      <AvailableMetricsComponents.link_button
        href={~p"/admin/metric_registry/categorization/metrics_order?category_id=#{@category.id}"}
        text={"Reorder Ungrouped Metrics (#{@ungrouped_metrics_count})"}
        icon="hero-arrows-up-down"
      />
    </div>
    """
  end

  attr :group, :map, required: true

  def group_actions(assigns) do
    ~H"""
    <div class="flex space-x-2">
      <.link
        navigate={
          ~p"/admin/metric_registry/categorization/metrics_order?category_id=#{@group.category_id}&group_id=#{@group.id}"
        }
        class="text-green-600 hover:text-green-900"
      >
        Reorder Metrics in Group
      </.link>
      <.link
        navigate={~p"/admin/metric_registry/categorization/groups/edit/#{@group.id}"}
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
        text="Back to Categorization"
        href={~p"/admin/metric_registry/categorization"}
        icon="hero-arrow-left"
      />
      <AvailableMetricsComponents.available_metrics_button
        text="Manage Categories"
        href={~p"/admin/metric_registry/categorization/categories"}
        icon="hero-rectangle-group"
      />
      <AvailableMetricsComponents.link_button
        icon="hero-plus"
        text="Create New Group"
        href={~p"/admin/metric_registry/categorization/groups/new"}
      />
    </div>
    """
  end

  @impl true
  def handle_event("filter", %{"category_id" => category_id}, socket) do
    category_id = if category_id == "", do: nil, else: String.to_integer(category_id)

    {:noreply,
     socket
     |> push_patch(
       to: ~p"/admin/metric_registry/categorization/groups?category_id=#{category_id || ""}"
     )}
  end

  def handle_event("reorder", %{"ids" => ids}, socket) do
    # Invoked by the reorder_controls component
    new_order = parse_reorder_ids(ids, "group")

    case Category.reorder_groups(new_order) do
      :ok ->
        categories_with_groups = Category.list_categories_with_groups()

        {:noreply,
         socket
         |> assign(categories_with_groups: categories_with_groups)
         |> put_flash(:info, "Groups reordered successfully.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to reorder groups: #{inspect(reason)}")}
    end
  end

  def handle_event("group-move-up", %{"id" => id}, socket) do
    id = String.to_integer(id)
    categories = socket.assigns.categories_with_groups

    case find_group_and_category(categories, id) do
      {group, category, index} when index > 0 ->
        prev_group = Enum.at(category.groups, index - 1)

        {:ok, _} = Category.swap_groups_display_orders(group, prev_group)

        categories_with_groups = Category.list_categories_with_groups()

        {:noreply, assign(socket, categories_with_groups: categories_with_groups)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("group-move-down", %{"id" => id}, socket) do
    id = String.to_integer(id)
    categories = socket.assigns.categories_with_groups

    case find_group_and_category(categories, id) do
      {group, category, index} when index < length(category.groups) - 1 ->
        next_group = Enum.at(category.groups, index + 1)

        {:ok, _} = Category.swap_groups_display_orders(group, next_group)

        categories_with_groups = Category.list_categories_with_groups()

        {:noreply, assign(socket, categories_with_groups: categories_with_groups)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    id = String.to_integer(id)

    case Category.get_group(id) do
      {:ok, group} ->
        {:ok, _} = Category.delete_group(group)

        # Refresh the categories with groups
        categories_with_groups = Category.list_categories_with_groups()

        {:noreply,
         socket
         |> assign(categories_with_groups: categories_with_groups)
         |> put_flash(:info, "Group deleted successfully.")}

      _ ->
        {:noreply,
         socket
         |> put_flash(:error, "Group not found.")}
    end
  end

  defp find_group_and_category(categories, group_id) do
    Enum.find_value(categories, fn category ->
      case Enum.find_index(category.groups, &(&1.id == group_id)) do
        nil ->
          nil

        index ->
          group = Enum.at(category.groups, index)
          {group, category, index}
      end
    end)
  end

  defp filter_categories(categories, nil), do: categories

  defp filter_categories(categories, category_id) do
    Enum.filter(categories, &(&1.id == category_id))
  end
end
