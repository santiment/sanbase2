defmodule SanbaseWeb.CategorizationLive.Index do
  use SanbaseWeb, :live_view

  import SanbaseWeb.CoreComponents
  alias Sanbase.Metric.Category
  alias Sanbase.Metric.Category.MetricCategoryMapping
  alias Sanbase.Metric.Registry
  alias Sanbase.Metric.Helper
  alias SanbaseWeb.AvailableMetricsComponents

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Metric Categorization",
       metrics: [],
       filtered_metrics: [],
       search_query: "",
       filter_source: "all",
       filter_status: "all",
       filter_ui_metadata: "all",
       filter_sanbase_display: "all",
       selected_category_id: nil,
       loading: true
     )
     |> load_data()}
  end

  @impl true
  def handle_params(params, _url, socket) do
    search_query = params["search"] || ""
    filter_source = params["source"] || "all"
    filter_status = params["status"] || "all"
    filter_ui_metadata = params["ui_metadata"] || "all"
    filter_sanbase_display = params["sanbase_display"] || "all"
    selected_category_id = params["category_id"]

    {:noreply,
     socket
     |> assign(
       search_query: search_query,
       filter_source: filter_source,
       filter_status: filter_status,
       filter_ui_metadata: filter_ui_metadata,
       filter_sanbase_display: filter_sanbase_display,
       selected_category_id: selected_category_id
     )
     |> apply_filters()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col justify-center w-full">
      <div class="text-gray-800 text-2xl mb-4">
        Metric Categorization
      </div>

      <.navigation />

      <div class="text-gray-600 whitespace-pre-line" phx-no-curly-interpolation>
        Assign metrics to categories and groups.
        One metric can have a single variant, like `price_usd`.
        One metric can generate many variants, like the single metric `mvrv_usd_{{timebound}}` generates mvrv_usd_1d, mvrv_usd_7d, mvrv_usd_30d, etc.
        Here we display and count these parametrized metrics as a single metric with multiple variants. The total number of variants is show with smaller font.
      </div>

      <.filters
        search_query={@search_query}
        filter_source={@filter_source}
        filter_status={@filter_status}
        filter_ui_metadata={@filter_ui_metadata}
        filter_sanbase_display={@filter_sanbase_display}
        selected_category_id={@selected_category_id}
        categories={@categories}
      />

      <.metrics_stats metrics={@metrics} filtered_metrics={@filtered_metrics} />

      <.metrics_table
        :if={!@loading}
        filtered_metrics={@filtered_metrics}
        categories_colors={@categories_colors}
      />

      <div :if={@loading} class="flex justify-center items-center py-12">
        <div class="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-500"></div>
        <p class="ml-4 text-gray-600">Loading metrics...</p>
      </div>
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
        text="Manage Categories"
        href={~p"/admin/metric_registry/categorization/categories"}
        icon="hero-rectangle-group"
      />
      <AvailableMetricsComponents.available_metrics_button
        text="Manage Groups"
        href={~p"/admin/metric_registry/categorization/groups"}
        icon="hero-user-group"
      />
      <AvailableMetricsComponents.available_metrics_button
        text="Preview UI Metadata Sidebar"
        href={~p"/admin/metric_registry/categorization/preview_sidebar"}
        icon="hero-eye"
      />
    </div>
    """
  end

  attr :search_query, :string, required: true
  attr :filter_source, :string, required: true
  attr :filter_status, :string, required: true
  attr :filter_ui_metadata, :string, required: true
  attr :filter_sanbase_display, :string, required: true
  attr :selected_category_id, :any, required: true
  attr :categories, :list, required: true

  def filters(assigns) do
    ~H"""
    <div class="bg-white p-4 rounded-lg shadow my-4">
      <.simple_form for={%{}} as={:filters} phx-change="filter">
        <div class="flex flex-col sm:flex-row sm:flex-wrap gap-4">
          <.input
            type="text"
            name="search"
            value={@search_query}
            label="Search metrics"
            placeholder="Type metric name..."
            phx-debounce="300"
          />

          <.input
            type="select"
            name="source"
            value={@filter_source}
            label="Source"
            options={[
              {"All Sources", "all"},
              {"Registry", "registry"},
              {"Code Module", "code"}
            ]}
          />

          <.input
            type="select"
            name="status"
            value={@filter_status}
            label="Status"
            options={[
              {"All", "all"},
              {"Categorized", "categorized"},
              {"Not Categorized", "not_categorized"}
            ]}
          />

          <.input
            type="select"
            name="category_id"
            value={@selected_category_id}
            label="Category"
            options={[
              {"All Categories", "all"},
              {"Not Categorized", "none"}
              | Enum.map(@categories, fn c -> {c.name, c.id} end)
            ]}
          />

          <.input
            type="select"
            name="ui_metadata"
            value={@filter_ui_metadata}
            label="UI Metadata"
            options={[
              {"All", "all"},
              {"Has any UI Metadata", "has_metadata"},
              {"All variants have UI Metadata", "has_metadata_all_variants"},
              {"Only some variants have UI Metadata", "has_metadata_only_some_variants"},
              {"No UI Metadata", "no_metadata"}
            ]}
          />

          <.input
            type="select"
            name="sanbase_display"
            value={@filter_sanbase_display}
            label="Sanbase Display"
            options={[
              {"All", "all"},
              {"Shown on Sanbase?", "shown"},
              {"Hidden from Sanbase", "hidden"}
            ]}
          />
        </div>
      </.simple_form>
    </div>
    """
  end

  attr :metrics, :list, required: true
  attr :filtered_metrics, :list, required: true

  def metrics_stats(assigns) do
    metrics_count = length(assigns.metrics)
    variants_count = Enum.sum_by(assigns.metrics, & &1.variants_count)

    filtered_count = length(assigns.filtered_metrics)
    filtered_variants_count = Enum.sum_by(assigns.filtered_metrics, & &1.variants_count)

    categorized_count = Enum.count(assigns.filtered_metrics, & &1.categorized?)

    categorized_variants_count =
      Enum.filter(assigns.filtered_metrics, & &1.categorized?) |> Enum.sum_by(& &1.variants_count)

    not_categorized_count = filtered_count - categorized_count
    not_categorized_variants_count = filtered_variants_count - categorized_variants_count

    has_ui_metadata_count = Enum.count(assigns.filtered_metrics, & &1.has_ui_metadata?)

    has_ui_metadata_variants_count =
      Enum.filter(assigns.filtered_metrics, & &1.has_ui_metadata?)
      |> Enum.sum_by(&length(&1.mapping.ui_metadata_list))

    show_on_sanbase_count = Enum.count(assigns.filtered_metrics, & &1.show_on_sanbase?)

    show_on_sanbase_variants_count =
      Enum.filter(assigns.filtered_metrics, & &1.has_ui_metadata?)
      |> Enum.flat_map(fn m -> m.mapping.ui_metadata_list || [] end)
      |> Enum.filter(fn m -> m.show_on_sanbase end)
      |> length()

    assigns =
      assigns
      |> assign(categorized_count: categorized_count)
      |> assign(categorized_variants_count: categorized_variants_count)
      |> assign(metrics_count: metrics_count)
      |> assign(variants_count: variants_count)
      |> assign(filtered_count: filtered_count)
      |> assign(filtered_variants_count: filtered_variants_count)
      |> assign(not_categorized_count: not_categorized_count)
      |> assign(not_categorized_variants_count: not_categorized_variants_count)
      |> assign(has_ui_metadata_count: has_ui_metadata_count)
      |> assign(has_ui_metadata_variants_count: has_ui_metadata_variants_count)
      |> assign(show_on_sanbase_count: show_on_sanbase_count)
      |> assign(show_on_sanbase_variants_count: show_on_sanbase_variants_count)

    ~H"""
    <div class="grid grid-cols-1 md:grid-cols-6 gap-4 mb-6">
      <div class="bg-white p-4 rounded-lg shadow">
        <div class="text-sm text-gray-600">Total Metrics</div>
        <div class="text-2xl font-bold text-gray-800">{@metrics_count}</div>
        <div class="text-xs text-gray-500">({@variants_count} variants)</div>
      </div>
      <div class="bg-white p-4 rounded-lg shadow">
        <div class="text-sm text-gray-600">Filtered</div>
        <div class="text-2xl font-bold text-gray-800">{@filtered_count}</div>
        <div class="text-xs text-gray-500">({@filtered_variants_count} variants)</div>
      </div>
      <div class="bg-white p-4 rounded-lg shadow">
        <div class="text-sm text-gray-600">Categorized</div>
        <div class="text-2xl font-bold text-green-600">{@categorized_count}</div>
        <div class="text-xs text-gray-500">({@categorized_variants_count} variants)</div>
      </div>
      <div class="bg-white p-4 rounded-lg shadow">
        <div class="text-sm text-gray-600">Not Categorized</div>
        <div class="text-2xl font-bold text-orange-600">{@not_categorized_count}</div>
        <div class="text-xs text-gray-500">({@not_categorized_variants_count} variants)</div>
      </div>
      <div class="bg-white p-4 rounded-lg shadow">
        <div class="text-sm text-gray-600">Has UI Metadata</div>
        <div class="text-2xl font-bold text-blue-600">{@has_ui_metadata_count}</div>
        <div class="text-xs text-gray-500">({@has_ui_metadata_variants_count} variants)</div>
      </div>
      <div class="bg-white p-4 rounded-lg shadow">
        <div class="text-sm text-gray-600">show on Sanbase</div>
        <div class="text-2xl font-bold text-purple-600">{@show_on_sanbase_count}</div>
        <div class="text-xs text-gray-500">({@show_on_sanbase_variants_count} variants)</div>
      </div>
    </div>
    """
  end

  attr :filtered_metrics, :list, required: true
  attr :categories_colors, :map, required: true

  def metrics_table(assigns) do
    ~H"""
    <div class="bg-white rounded-lg shadow overflow-hidden">
      <div class="overflow-x-auto">
        <table class="min-w-full divide-y divide-gray-200">
          <thead class="bg-gray-50">
            <tr>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Metric
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Source
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Category
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Group
              </th>
              <th class="px-2 py-3 text-center text-xs font-medium text-gray-500 uppercase tracking-wider">
                UI
              </th>
              <th class="px-2 py-3 text-center text-xs font-medium text-gray-500 uppercase tracking-wider">
                Sanbase
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Actions
              </th>
            </tr>
          </thead>
          <tbody class="bg-white divide-y divide-gray-200">
            <.metric_row
              :for={metric <- @filtered_metrics}
              metric={metric}
              categories_colors={@categories_colors}
            />
          </tbody>
        </table>
      </div>

      <div :if={@filtered_metrics == []} class="px-6 py-12 text-center text-gray-500">
        No metrics found matching your filters.
      </div>
    </div>
    """
  end

  attr :metric, :map, required: true
  attr :categories_colors, :map, required: true

  def metric_row(assigns) do
    ~H"""
    <tr class={Map.get(@categories_colors, @metric.category_name)}>
      <td class="px-6 py-4 max-w-[320px] break-words">
        <div class="flex flex-col">
          <div class="text-sm font-medium text-gray-900">{@metric.metric}</div>
          <div class="text-xs text-gray-500">
            {@metric.human_readable_name}
          </div>

          <div :if={@metric.variants_count >= 2} class="text-xs text-purple-800">
            (#{@metric.variants_count} variants)
          </div>
        </div>
      </td>
      <td class="px-6 py-4 whitespace-nowrap">
        <span
          :if={@metric.source_type == "registry"}
          class="px-2 py-1 text-xs font-medium rounded bg-blue-100 text-blue-800"
        >
          <.link navigate={~p"/admin/metric_registry/show/#{@metric.source_id}"}>
            {@metric.source_display}
          </.link>
        </span>

        <span
          :if={@metric.source_type == "code"}
          class="px-2 py-1 text-xs font-medium rounded bg-purple-100 text-purple-800"
        >
          {@metric.source_display}
        </span>
      </td>
      <td class="px-6 py-4 whitespace-nowrap">
        <div :if={@metric.category_name} class="text-sm text-gray-900">
          {@metric.category_name}
        </div>
        <div :if={!@metric.category_name} class="text-sm text-gray-400 italic">
          Not assigned
        </div>
      </td>
      <td class="px-6 py-4 max-w-[144px] break-normal">
        <div :if={@metric.group_name} class="text-sm text-gray-900">
          {@metric.group_name}
        </div>
        <div :if={!@metric.group_name} class="text-sm text-gray-400 italic">
          -
        </div>
      </td>
      <td class="px-2 py-4 whitespace-nowrap text-center">
        <.icon :if={@metric.has_ui_metadata?} name="hero-check-circle" class="w-5 h-5 text-green-600" />
        <.icon :if={!@metric.has_ui_metadata?} name="hero-x-circle" class="w-5 h-5 text-red-400" />
      </td>

      <td class="px-2 py-4 whitespace-nowrap text-center">
        <.icon :if={@metric.show_on_sanbase?} name="hero-eye" class="w-5 h-5 text-green-600" />
        <.icon :if={!@metric.show_on_sanbase?} name="hero-eye-slash" class="w-5 h-5 text-gray-400" />
      </td>

      <td class="px-6 py-4 whitespace-nowrap text-sm">
        <div class="flex flex-col space-y-1">
          <.link
            :if={!@metric.mapping_id}
            navigate={
              ~p"/admin/metric_registry/categorization/mappings/new?#{build_new_params(@metric)}"
            }
            class="text-green-600 hover:text-green-900"
          >
            Assign to Category
          </.link>
          <.link
            :if={@metric.mapping_id}
            navigate={
              ~p"/admin/metric_registry/categorization/ui_metadata/list/#{@metric.mapping_id}"
            }
            class="text-purple-600 hover:text-purple-900"
          >
            {"Manage UI Metadata (#{length(@metric.mapping.ui_metadata_list)})"}
          </.link>

          <.link
            :if={@metric.mapping_id}
            navigate={~p"/admin/metric_registry/categorization/mappings/edit/#{@metric.mapping_id}"}
            class="text-blue-600 hover:text-blue-900"
          >
            Edit Categorization
          </.link>
          <button
            :if={@metric.mapping_id}
            phx-click="delete_mapping"
            phx-value-id={@metric.mapping_id}
            class="text-red-600 hover:text-red-900 text-left"
            data-confirm="Are you sure you want to remove this categorization?"
          >
            Remove Categorization
          </button>
        </div>
      </td>
    </tr>
    """
  end

  @impl true
  def handle_event("filter", params, socket) do
    search_query = params["search"] || ""
    filter_source = params["source"] || "all"
    filter_status = params["status"] || "all"
    filter_ui_metadata = params["ui_metadata"] || "all"
    filter_sanbase_display = params["sanbase_display"] || "all"
    category_id = params["category_id"] || :all

    query_params =
      %{}
      |> maybe_add_param("search", search_query)
      |> maybe_add_param("source", filter_source, "all")
      |> maybe_add_param("status", filter_status, "all")
      |> maybe_add_param("ui_metadata", filter_ui_metadata, "all")
      |> maybe_add_param("sanbase_display", filter_sanbase_display, "all")
      |> maybe_add_param("category_id", category_id)

    {:noreply, push_patch(socket, to: ~p"/admin/metric_registry/categorization?#{query_params}")}
  end

  def handle_event("delete_mapping", %{"id" => id}, socket) do
    id = String.to_integer(id)

    case MetricCategoryMapping.get(id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Mapping not found")}

      mapping ->
        case Category.delete_mapping(mapping) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:info, "Mapping removed successfully")
             |> load_data()
             |> apply_filters()}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to remove mapping")}
        end
    end
  end

  defp load_data(socket) do
    categories = Category.list_categories()
    mappings = MetricCategoryMapping.list_all()
    ui_metadata_list = Category.list_all_ui_metadata()

    ui_metadata_by_mapping_id =
      ui_metadata_list
      |> Enum.group_by(& &1.metric_category_mapping_id)

    mappings_by_registry_id =
      mappings
      |> Enum.filter(& &1.metric_registry_id)
      |> Map.new(&{&1.metric_registry_id, &1})

    mappings_by_module_metric =
      mappings
      |> Enum.filter(&(&1.module && &1.metric))
      |> Map.new(&{{&1.module, &1.metric}, &1})

    registry_metrics = get_registry_metrics(mappings_by_registry_id, ui_metadata_by_mapping_id)
    code_metrics = get_code_metrics(mappings_by_module_metric, ui_metadata_by_mapping_id)

    all_metrics = registry_metrics ++ code_metrics

    all_metrics =
      Enum.sort_by(
        all_metrics,
        fn m -> {m.category_display_order, m.group_display_order, m.display_order} end,
        :asc
      )

    categories_colors =
      Enum.with_index(categories)
      |> Map.new(fn {category, index} ->
        {category.name,
         if(rem(index, 2) == 0,
           do: "bg-white hover:bg-neutral-200",
           else: "bg-neutral-100 hover:bg-neutral-200"
         )}
      end)

    socket
    |> assign(
      metrics: all_metrics,
      categories: categories,
      categories_colors: categories_colors,
      loading: false
    )
  end

  defp get_registry_metrics(mappings_by_registry_id, ui_metadata_by_mapping_id) do
    Registry.all()
    |> Enum.map(fn registry ->
      mapping = Map.get(mappings_by_registry_id, registry.id)
      ui_metadata_list = mapping && Map.get(ui_metadata_by_mapping_id, mapping.id, [])

      has_ui_metadata? = ui_metadata_list != [] && ui_metadata_list != nil
      show_on_sanbase? = has_ui_metadata? && Enum.any?(ui_metadata_list, & &1.show_on_sanbase)

      all_variants_have_ui_metadata? =
        if registry.parameters == [] do
          has_ui_metadata?
        else
          has_ui_metadata? and length(ui_metadata_list) == length(registry.parameters)
        end

      %{
        metric: registry.metric,
        human_readable_name: registry.human_readable_name,
        source_type: "registry",
        source_display: "Registry",
        source_id: registry.id,
        module: nil,
        mapping: mapping,
        mapping_id: mapping && mapping.id,
        category_id: mapping && mapping.category_id,
        category_name: mapping && mapping.category && mapping.category.name,
        category_display_order: mapping && mapping.category && mapping.category.display_order,
        group_id: mapping && mapping.group_id,
        group_name: mapping && mapping.group && mapping.group.name,
        # The ungrouped metrics should appear first
        group_display_order: (mapping && mapping.group && mapping.group.display_order) || -1,
        display_order: mapping && mapping.display_order,
        categorized?: not is_nil(mapping),
        has_ui_metadata?: has_ui_metadata?,
        all_variants_have_ui_metadata?: all_variants_have_ui_metadata?,
        show_on_sanbase?: show_on_sanbase?,
        variants_count: max(1, length(registry.parameters))
      }
    end)
  end

  defp get_code_metrics(mappings_by_module_metric, ui_metadata_by_mapping_id) do
    registry_metrics_mapset =
      Registry.all()
      |> Registry.resolve()
      |> Enum.map(& &1.metric)
      |> MapSet.new()

    metric_to_module_map = Helper.metric_to_module_map()

    metric_to_module_map
    |> Enum.reject(fn {metric, _module} -> metric in registry_metrics_mapset end)
    |> Enum.map(fn {metric, module} ->
      module_str = inspect(module)
      mapping = Map.get(mappings_by_module_metric, {module_str, metric})
      ui_metadata_list = mapping && Map.get(ui_metadata_by_mapping_id, mapping.id, [])
      {:ok, human_readable_name} = Sanbase.Metric.human_readable_name(metric)

      has_ui_metadata? = ui_metadata_list != [] && ui_metadata_list != nil
      show_on_sanbase? = has_ui_metadata? && Enum.any?(ui_metadata_list, & &1.show_on_sanbase)

      %{
        metric: metric,
        human_readable_name: human_readable_name,
        source_type: "code",
        source_display: format_module_name(module),
        source_id: nil,
        module: module_str,
        mapping: mapping,
        mapping_id: mapping && mapping.id,
        category_id: mapping && mapping.category_id,
        category_name: mapping && mapping.category && mapping.category.name,
        category_display_order: mapping && mapping.category && mapping.category.display_order,
        group_id: mapping && mapping.group_id,
        group_name: mapping && mapping.group && mapping.group.name,
        # The ungrouped metrics should appear first
        group_display_order: (mapping && mapping.group && mapping.group.display_order) || -1,
        display_order: mapping && mapping.display_order,
        categorized?: not is_nil(mapping),
        has_ui_metadata?: has_ui_metadata?,
        all_variants_have_ui_metadata?: true,
        show_on_sanbase?: show_on_sanbase?,
        variants_count: 1
      }
    end)
  end

  defp apply_filters(socket) do
    %{
      metrics: metrics,
      search_query: search_query,
      filter_source: filter_source,
      filter_status: filter_status,
      filter_ui_metadata: filter_ui_metadata,
      filter_sanbase_display: filter_sanbase_display,
      selected_category_id: selected_category_id
    } = socket.assigns

    filtered_metrics =
      metrics
      |> filter_by_search(search_query)
      |> filter_by_source(filter_source)
      |> filter_by_status(filter_status)
      |> filter_by_ui_metadata(filter_ui_metadata)
      |> filter_by_sanbase_display(filter_sanbase_display)
      |> filter_by_category(selected_category_id)

    assign(socket, filtered_metrics: filtered_metrics)
  end

  defp filter_by_search(metrics, ""), do: metrics

  defp filter_by_search(metrics, query) do
    query_lower = String.downcase(query)

    Enum.filter(metrics, fn metric ->
      String.contains?(String.downcase(metric.metric), query_lower) ||
        (metric.human_readable_name &&
           String.contains?(String.downcase(metric.human_readable_name), query_lower))
    end)
  end

  defp filter_by_source(metrics, "all"), do: metrics
  defp filter_by_source(metrics, source), do: Enum.filter(metrics, &(&1.source_type == source))

  defp filter_by_status(metrics, "all"), do: metrics

  defp filter_by_status(metrics, "categorized"),
    do: Enum.filter(metrics, & &1.categorized?)

  defp filter_by_status(metrics, "not_categorized"),
    do: Enum.filter(metrics, &(not &1.categorized?))

  defp filter_by_category(metrics, nil), do: metrics
  defp filter_by_category(metrics, "all"), do: metrics

  defp filter_by_category(metrics, "none") do
    Enum.filter(metrics, &is_nil(&1.category_id))
  end

  defp filter_by_category(metrics, category_id) when is_binary(category_id) do
    category_id = String.to_integer(category_id)
    Enum.filter(metrics, &(&1.category_id == category_id))
  end

  defp filter_by_category(metrics, category_id) when is_integer(category_id) do
    Enum.filter(metrics, &(&1.category_id == category_id))
  end

  defp filter_by_ui_metadata(metrics, "all"), do: metrics

  defp filter_by_ui_metadata(metrics, "has_metadata"),
    do: Enum.filter(metrics, & &1.has_ui_metadata?)

  defp filter_by_ui_metadata(metrics, "has_metadata_all_variants"),
    do: Enum.filter(metrics, & &1.all_variants_have_ui_metadata?)

  defp filter_by_ui_metadata(metrics, "has_metadata_only_some_variants"),
    do: Enum.filter(metrics, &(&1.has_ui_metadata? and not &1.all_variants_have_ui_metadata?))

  defp filter_by_ui_metadata(metrics, "no_metadata"),
    do: Enum.filter(metrics, &(not &1.has_ui_metadata?))

  defp filter_by_sanbase_display(metrics, "all"), do: metrics

  defp filter_by_sanbase_display(metrics, "shown"),
    do: Enum.filter(metrics, & &1.show_on_sanbase?)

  defp filter_by_sanbase_display(metrics, "hidden"),
    do: Enum.filter(metrics, &(not &1.show_on_sanbase?))

  defp format_module_name(module) do
    module
    |> inspect()
    |> String.split(".")
    |> List.last()
  end

  defp build_new_params(metric) do
    params = %{}

    params =
      if metric.source_type == "registry" do
        Map.put(params, "metric_registry_id", metric.source_id)
      else
        params
        |> Map.put("module", metric.module)
        |> Map.put("metric", metric.metric)
      end

    params
  end

  defp maybe_add_param(params, _key, ""), do: params
  defp maybe_add_param(params, _key, nil), do: params
  defp maybe_add_param(params, key, value), do: Map.put(params, key, value)

  defp maybe_add_param(params, _key, value, default) when value == default, do: params
  defp maybe_add_param(params, key, value, _default), do: Map.put(params, key, value)
end
