defmodule SanbaseWeb.CategorizationLive.PreviewSidebar do
  use SanbaseWeb, :live_view

  import SanbaseWeb.CoreComponents
  alias Sanbase.Metric.Category
  alias Sanbase.Metric.Category.MetricCategoryMapping
  alias SanbaseWeb.AvailableMetricsComponents

  @impl true
  def mount(_params, _session, socket) do
    projects = load_projects()

    {:ok,
     socket
     |> assign(
       page_title: "UI Metadata Sidebar Preview",
       search_query: "",
       selected_category_id: nil,
       selected_project_slug: nil,
       projects: projects,
       expanded_categories: MapSet.new(),
       expanded_groups: MapSet.new(),
       loading: true
     )
     |> load_data()
     |> initialize_expanded_state()
     |> apply_filters()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-row h-screen">
      <div class="p-3 border-b bg-white">
        <h1 class="text-lg font-bold text-gray-800">UI Metadata Sidebar Preview</h1>
        <AvailableMetricsComponents.available_metrics_button
          text="Back"
          href={~p"/admin/metric_registry/categorization"}
          icon="hero-arrow-left"
        />

        <.filters
          search_query={@search_query}
          selected_category_id={@selected_category_id}
          selected_project_slug={@selected_project_slug}
          categories={@categories}
          projects={@projects}
        />
      </div>

      <div class="flex-1 overflow-hidden flex">
        <.sidebar
          :if={!@loading}
          filtered_hierarchy={@filtered_hierarchy}
          expanded_categories={@expanded_categories}
          expanded_groups={@expanded_groups}
        />

        <div :if={@loading} class="flex-1 flex justify-center items-center">
          <div class="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-500"></div>
          <p class="ml-4 text-gray-600">Loading metrics...</p>
        </div>

        <div
          :if={!@loading && @filtered_hierarchy == []}
          class="flex-1 flex justify-center items-center"
        >
          <p class="text-gray-500">No metrics with UI metadata found matching your filters.</p>
        </div>
      </div>
    </div>
    """
  end

  attr :search_query, :string, required: true
  attr :selected_category_id, :any, required: true
  attr :selected_project_slug, :any, required: true
  attr :categories, :list, required: true
  attr :projects, :list, required: true

  def filters(assigns) do
    ~H"""
    <.simple_form for={%{}} as={:filters} phx-change="filter" class="flex items-end gap-2">
      <.input
        type="text"
        name="search"
        value={@search_query}
        label="Search"
        placeholder="Metric name..."
        phx-debounce="300"
        class="flex-1 min-w-0"
      />

      <.input
        type="select"
        name="project_slug"
        value={@selected_project_slug}
        label="Project"
        options={[
          {"All Projects", "all"}
          | Enum.map(@projects, fn p -> {"#{p.name} (#{p.ticker})", p.slug} end)
        ]}
        class="min-w-[200px]"
      />

      <.input
        type="select"
        name="category_id"
        value={@selected_category_id}
        label="Category"
        options={[
          {"All", "all"}
          | Enum.map(@categories, fn c -> {c.name, c.id} end)
        ]}
        class="min-w-[150px]"
      />

      <button
        type="button"
        phx-click="expand_all"
        class="px-3 py-2 text-xs font-medium text-gray-700 bg-white border border-gray-300 rounded hover:bg-gray-50 whitespace-nowrap"
      >
        <.icon name="hero-chevron-down" class="w-3 h-3 inline" /> Expand
      </button>
      <button
        type="button"
        phx-click="collapse_all"
        class="px-3 py-2 text-xs font-medium text-gray-700 bg-white border border-gray-300 rounded hover:bg-gray-50 whitespace-nowrap"
      >
        <.icon name="hero-chevron-up" class="w-3 h-3 inline" /> Collapse
      </button>
    </.simple_form>
    """
  end

  attr :filtered_hierarchy, :list, required: true
  attr :expanded_categories, :map, required: true
  attr :expanded_groups, :map, required: true

  def sidebar(assigns) do
    ~H"""
    <aside class="w-80 bg-gray-50 border-r overflow-y-auto">
      <nav class="p-2">
        <div :for={category <- @filtered_hierarchy} class="mb-1">
          <.category_item
            category={category}
            expanded_categories={@expanded_categories}
            expanded_groups={@expanded_groups}
          />
        </div>
      </nav>
    </aside>
    """
  end

  attr :category, :map, required: true
  attr :expanded_categories, :map, required: true
  attr :expanded_groups, :map, required: true

  def category_item(assigns) do
    is_expanded = MapSet.member?(assigns.expanded_categories, assigns.category.id)
    assigns = assign(assigns, :is_expanded, is_expanded)

    ~H"""
    <div class="mb-1">
      <button
        phx-click="toggle_category"
        phx-value-id={@category.id}
        class="w-full flex items-center justify-between px-3 py-2 text-sm font-semibold text-gray-900 bg-white border border-gray-200 rounded-lg hover:bg-gray-100"
      >
        <span>{@category.name}</span>
        <.icon
          name={if @is_expanded, do: "hero-chevron-down", else: "hero-chevron-right"}
          class="w-4 h-4"
        />
      </button>

      <div :if={@is_expanded} class="mt-1 ml-4 space-y-1">
        <div :if={@category.ungrouped_mappings != []} class="space-y-1">
          <div :for={mapping <- @category.ungrouped_mappings} class="space-y-0.5">
            <.metric_item
              :for={ui_meta <- mapping.ui_metadata_list}
              ui_meta={ui_meta}
              mapping={mapping}
            />
          </div>
        </div>

        <div :for={group <- @category.groups} class="mt-2">
          <.group_item group={group} expanded_groups={@expanded_groups} />
        </div>
      </div>
    </div>
    """
  end

  attr :group, :map, required: true
  attr :expanded_groups, :map, required: true

  def group_item(assigns) do
    is_expanded = MapSet.member?(assigns.expanded_groups, assigns.group.id)
    assigns = assign(assigns, :is_expanded, is_expanded)

    ~H"""
    <div class="mb-1">
      <button
        phx-click="toggle_group"
        phx-value-id={@group.id}
        class="w-full flex items-center justify-between px-3 py-2 text-sm font-medium text-gray-800 bg-gray-100 border border-gray-200 rounded hover:bg-gray-200"
      >
        <span>{@group.name}</span>
        <.icon
          name={if @is_expanded, do: "hero-chevron-down", else: "hero-chevron-right"}
          class="w-4 h-4"
        />
      </button>

      <div :if={@is_expanded} class="mt-1 ml-4 space-y-0.5">
        <div :for={mapping <- @group.mappings} class="space-y-0.5">
          <.metric_item
            :for={ui_meta <- mapping.ui_metadata_list}
            ui_meta={ui_meta}
            mapping={mapping}
          />
        </div>
      </div>
    </div>
    """
  end

  attr :ui_meta, :map, required: true
  attr :mapping, :map, required: true

  def metric_item(assigns) do
    display_name = get_metric_display_name(assigns.ui_meta, assigns.mapping)
    assigns = assign(assigns, :display_name, display_name)

    ~H"""
    <div class="px-3 py-2 text-sm text-gray-700 bg-white border border-gray-200 rounded hover:bg-blue-50">
      {@display_name}
    </div>
    """
  end

  @impl true
  def handle_event("filter", params, socket) do
    search_query = params["search"] || ""
    category_id = params["category_id"]
    project_slug = params["project_slug"]

    selected_category_id =
      case category_id do
        "all" -> nil
        nil -> nil
        id when is_binary(id) -> String.to_integer(id)
        id -> id
      end

    selected_project_slug =
      case project_slug do
        "all" -> nil
        nil -> nil
        slug -> slug
      end

    {:noreply,
     socket
     |> assign(
       search_query: search_query,
       selected_category_id: selected_category_id,
       selected_project_slug: selected_project_slug
     )
     |> apply_filters()}
  end

  def handle_event("toggle_category", %{"id" => id}, socket) do
    category_id = String.to_integer(id)

    expanded_categories =
      if MapSet.member?(socket.assigns.expanded_categories, category_id) do
        MapSet.delete(socket.assigns.expanded_categories, category_id)
      else
        MapSet.put(socket.assigns.expanded_categories, category_id)
      end

    {:noreply, assign(socket, expanded_categories: expanded_categories)}
  end

  def handle_event("toggle_group", %{"id" => id}, socket) do
    group_id = String.to_integer(id)

    expanded_groups =
      if MapSet.member?(socket.assigns.expanded_groups, group_id) do
        MapSet.delete(socket.assigns.expanded_groups, group_id)
      else
        MapSet.put(socket.assigns.expanded_groups, group_id)
      end

    {:noreply, assign(socket, expanded_groups: expanded_groups)}
  end

  def handle_event("expand_all", _params, socket) do
    all_category_ids =
      socket.assigns.categories_hierarchy
      |> Enum.map(& &1.id)
      |> MapSet.new()

    all_group_ids =
      socket.assigns.categories_hierarchy
      |> Enum.flat_map(& &1.groups)
      |> Enum.map(& &1.id)
      |> MapSet.new()

    {:noreply,
     socket
     |> assign(expanded_categories: all_category_ids, expanded_groups: all_group_ids)}
  end

  def handle_event("collapse_all", _params, socket) do
    {:noreply,
     socket
     |> assign(expanded_categories: MapSet.new(), expanded_groups: MapSet.new())}
  end

  defp load_data(socket) do
    categories_hierarchy = build_hierarchy()
    categories = Enum.map(categories_hierarchy, fn c -> %{id: c.id, name: c.name} end)

    socket
    |> assign(
      categories_hierarchy: categories_hierarchy,
      categories: categories,
      loading: false
    )
  end

  defp initialize_expanded_state(socket) do
    all_category_ids =
      socket.assigns.categories_hierarchy
      |> Enum.map(& &1.id)
      |> MapSet.new()

    all_group_ids =
      socket.assigns.categories_hierarchy
      |> Enum.flat_map(& &1.groups)
      |> Enum.map(& &1.id)
      |> MapSet.new()

    socket
    |> assign(expanded_categories: all_category_ids, expanded_groups: all_group_ids)
  end

  defp build_hierarchy do
    categories = Category.list_categories()

    categories
    |> Enum.map(fn category ->
      ungrouped_mappings = get_ungrouped_mappings_with_ui_metadata(category.id)
      groups = get_groups_with_mappings(category.id)

      %{
        id: category.id,
        name: category.name,
        display_order: category.display_order,
        ungrouped_mappings: ungrouped_mappings,
        groups: groups
      }
    end)
    |> Enum.filter(fn category ->
      category.ungrouped_mappings != [] || category.groups != []
    end)
  end

  defp get_ungrouped_mappings_with_ui_metadata(category_id) do
    MetricCategoryMapping.get_ungrouped_by_category(category_id)
    |> Enum.filter(fn mapping -> mapping.ui_metadata_list != [] end)
    |> Enum.map(&build_mapping_structure/1)
  end

  defp get_groups_with_mappings(category_id) do
    Category.list_groups_by_category(category_id)
    |> Enum.map(&build_group_structure(&1, category_id))
    |> Enum.filter(fn group -> group.mappings != [] end)
  end

  defp build_group_structure(group, category_id) do
    mappings =
      MetricCategoryMapping.get_by_category_and_group(category_id, group.id)
      |> Enum.filter(fn mapping -> mapping.ui_metadata_list != [] end)
      |> Enum.map(&build_mapping_structure/1)

    %{
      id: group.id,
      name: group.name,
      display_order: group.display_order,
      mappings: mappings
    }
  end

  defp build_mapping_structure(mapping) do
    ui_metadata_list = sort_ui_metadata(mapping.ui_metadata_list)

    %{
      id: mapping.id,
      metric: mapping.metric,
      metric_registry: mapping.metric_registry,
      module: mapping.module,
      ui_metadata_list: ui_metadata_list
    }
  end

  defp sort_ui_metadata(ui_metadata_list) do
    Enum.sort_by(
      ui_metadata_list,
      fn ui_meta -> {ui_meta.display_order_in_mapping || 999_999, ui_meta.id} end,
      :asc
    )
  end

  defp apply_filters(socket) do
    %{
      categories_hierarchy: categories_hierarchy,
      search_query: search_query,
      selected_category_id: selected_category_id,
      selected_project_slug: selected_project_slug
    } = socket.assigns

    filtered_hierarchy =
      categories_hierarchy
      |> filter_by_category(selected_category_id)
      |> filter_by_project(selected_project_slug)
      |> filter_by_search(search_query)

    assign(socket, filtered_hierarchy: filtered_hierarchy)
  end

  defp filter_by_category(hierarchy, nil), do: hierarchy

  defp filter_by_category(hierarchy, category_id) do
    Enum.filter(hierarchy, fn category -> category.id == category_id end)
  end

  defp filter_by_project(hierarchy, nil), do: hierarchy

  defp filter_by_project(hierarchy, project_slug) do
    available_metrics = get_available_metrics_for_project(project_slug)
    available_metrics_set = MapSet.new(available_metrics)

    hierarchy
    |> Enum.map(&filter_category_by_available_metrics(&1, available_metrics_set))
    |> Enum.filter(&category_has_results?/1)
  end

  defp filter_category_by_available_metrics(category, available_metrics_set) do
    ungrouped_mappings =
      Enum.filter(category.ungrouped_mappings, fn mapping ->
        metric_available?(mapping, available_metrics_set)
      end)

    groups =
      category.groups
      |> Enum.map(fn group ->
        mappings =
          Enum.filter(group.mappings, fn mapping ->
            metric_available?(mapping, available_metrics_set)
          end)

        Map.put(group, :mappings, mappings)
      end)
      |> Enum.filter(fn group -> group.mappings != [] end)

    category
    |> Map.put(:ungrouped_mappings, ungrouped_mappings)
    |> Map.put(:groups, groups)
  end

  defp metric_available?(mapping, available_metrics_set) do
    metric_name = get_base_metric_name(mapping)
    MapSet.member?(available_metrics_set, metric_name)
  end

  defp get_base_metric_name(mapping) do
    cond do
      mapping.metric_registry && mapping.metric_registry.metric ->
        mapping.metric_registry.metric

      mapping.metric ->
        mapping.metric

      true ->
        nil
    end
  end

  defp get_available_metrics_for_project(project_slug) do
    case Sanbase.Metric.available_metrics_for_selector(%{slug: project_slug}) do
      {:ok, metrics} -> metrics
      _ -> []
    end
  end

  defp filter_by_search(hierarchy, ""), do: hierarchy

  defp filter_by_search(hierarchy, query) do
    query_lower = String.downcase(query)

    hierarchy
    |> Enum.map(&filter_category_by_search(&1, query_lower))
    |> Enum.filter(&category_has_results?/1)
  end

  defp filter_category_by_search(category, query_lower) do
    ungrouped_mappings =
      Enum.filter(category.ungrouped_mappings, &mapping_matches_search?(&1, query_lower))

    groups =
      category.groups
      |> Enum.map(&filter_group_by_search(&1, query_lower))
      |> Enum.filter(fn group -> group.mappings != [] end)

    category
    |> Map.put(:ungrouped_mappings, ungrouped_mappings)
    |> Map.put(:groups, groups)
  end

  defp filter_group_by_search(group, query_lower) do
    mappings = Enum.filter(group.mappings, &mapping_matches_search?(&1, query_lower))
    Map.put(group, :mappings, mappings)
  end

  defp category_has_results?(category) do
    category.ungrouped_mappings != [] || category.groups != []
  end

  defp mapping_matches_search?(mapping, query_lower) do
    Enum.any?(mapping.ui_metadata_list, fn ui_meta ->
      display_name = get_metric_display_name(ui_meta, mapping)
      String.contains?(String.downcase(display_name), query_lower)
    end)
  end

  defp get_metric_display_name(ui_metadata, mapping) do
    ui_metadata.ui_human_readable_name ||
      get_registry_name(mapping) ||
      get_metric_name(mapping) ||
      "Unknown Metric"
  end

  defp get_registry_name(mapping) do
    mapping.metric_registry && mapping.metric_registry.human_readable_name
  end

  defp get_metric_name(mapping) do
    if mapping.metric do
      case Sanbase.Metric.human_readable_name(mapping.metric) do
        {:ok, name} -> name
        _ -> mapping.metric
      end
    end
  end

  defp load_projects do
    Sanbase.MCP.DataCatalog.get_all_projects()
    |> Enum.sort_by(& &1.name)
  end
end
