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
    selected_category_id = params["category_id"]

    {:noreply,
     socket
     |> assign(
       search_query: search_query,
       filter_source: filter_source,
       filter_status: filter_status,
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

      <div class="text-gray-600">
        <p>
          Assign metrics to categories and groups. This is the layer between the metric definition
          (in registry or code) and the UI display order.
        </p>
      </div>

      <.filters
        search_query={@search_query}
        filter_source={@filter_source}
        filter_status={@filter_status}
        selected_category_id={@selected_category_id}
        categories={@categories}
      />

      <.metrics_stats metrics={@metrics} filtered_metrics={@filtered_metrics} />

      <.metrics_table :if={!@loading} filtered_metrics={@filtered_metrics} />

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
    </div>
    """
  end

  attr :search_query, :string, required: true
  attr :filter_source, :string, required: true
  attr :filter_status, :string, required: true
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
              {"All Categories", ""}
              | Enum.map(@categories, fn c -> {c.name, c.id} end)
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
    categorized_count = Enum.count(assigns.filtered_metrics, & &1.categorized?)
    not_categorized_count = length(assigns.filtered_metrics) - categorized_count

    assigns =
      assigns
      |> assign(categorized_count: categorized_count)
      |> assign(not_categorized_count: not_categorized_count)

    ~H"""
    <div class="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
      <div class="bg-white p-4 rounded-lg shadow">
        <div class="text-sm text-gray-600">Total Metrics</div>
        <div class="text-2xl font-bold text-gray-800">{length(@metrics)}</div>
      </div>
      <div class="bg-white p-4 rounded-lg shadow">
        <div class="text-sm text-gray-600">Filtered</div>
        <div class="text-2xl font-bold text-gray-800">{length(@filtered_metrics)}</div>
      </div>
      <div class="bg-white p-4 rounded-lg shadow">
        <div class="text-sm text-gray-600">Categorized</div>
        <div class="text-2xl font-bold text-green-600">{@categorized_count}</div>
      </div>
      <div class="bg-white p-4 rounded-lg shadow">
        <div class="text-sm text-gray-600">Not Categorized</div>
        <div class="text-2xl font-bold text-orange-600">{@not_categorized_count}</div>
      </div>
    </div>
    """
  end

  attr :filtered_metrics, :list, required: true

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
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Actions
              </th>
            </tr>
          </thead>
          <tbody class="bg-white divide-y divide-gray-200">
            <.metric_row :for={metric <- @filtered_metrics} metric={metric} />
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

  def metric_row(assigns) do
    ~H"""
    <tr class="hover:bg-gray-50">
      <td class="px-6 py-4 whitespace-nowrap">
        <div class="flex flex-col">
          <div class="text-sm font-medium text-gray-900">{@metric.metric}</div>
          <div class="text-xs text-gray-500">
            {@metric.human_readable_name}
          </div>
        </div>
      </td>
      <td class="px-6 py-4 whitespace-nowrap">
        <span class={[
          "px-2 py-1 text-xs font-medium rounded",
          @metric.source_type == "registry" && "bg-blue-100 text-blue-800",
          @metric.source_type == "code" && "bg-purple-100 text-purple-800"
        ]}>
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
      <td class="px-6 py-4 whitespace-nowrap">
        <div :if={@metric.group_name} class="text-sm text-gray-900">
          {@metric.group_name}
        </div>
        <div :if={!@metric.group_name} class="text-sm text-gray-400 italic">
          -
        </div>
      </td>
      <td class="px-6 py-4 whitespace-nowrap text-sm">
        <.link
          :if={@metric.mapping_id}
          navigate={~p"/admin/metric_registry/categorization/mappings/edit/#{@metric.mapping_id}"}
          class="text-blue-600 hover:text-blue-900 mr-3"
        >
          Edit
        </.link>
        <.link
          :if={!@metric.mapping_id}
          navigate={
            ~p"/admin/metric_registry/categorization/mappings/new?#{build_new_params(@metric)}"
          }
          class="text-green-600 hover:text-green-900"
        >
          Assign
        </.link>
        <button
          :if={@metric.mapping_id}
          phx-click="delete_mapping"
          phx-value-id={@metric.mapping_id}
          class="text-red-600 hover:text-red-900"
          data-confirm="Are you sure you want to remove this categorization?"
        >
          Remove
        </button>
      </td>
    </tr>
    """
  end

  @impl true
  def handle_event("filter", params, socket) do
    search_query = params["search"] || ""
    filter_source = params["source"] || "all"
    filter_status = params["status"] || "all"
    category_id = params["category_id"] || ""

    query_params =
      %{}
      |> maybe_add_param("search", search_query)
      |> maybe_add_param("source", filter_source, "all")
      |> maybe_add_param("status", filter_status, "all")
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

    mappings_by_registry_id =
      mappings
      |> Enum.filter(& &1.metric_registry_id)
      |> Map.new(&{&1.metric_registry_id, &1})

    mappings_by_module_metric =
      mappings
      |> Enum.filter(&(&1.module && &1.metric))
      |> Map.new(&{{&1.module, &1.metric}, &1})

    registry_metrics = get_registry_metrics(mappings_by_registry_id)
    code_metrics = get_code_metrics(mappings_by_module_metric)

    all_metrics = registry_metrics ++ code_metrics

    socket
    |> assign(
      metrics: all_metrics,
      categories: categories,
      loading: false
    )
  end

  defp get_registry_metrics(mappings_by_registry_id) do
    Registry.all()
    |> Registry.resolve()
    |> Enum.map(fn registry ->
      mapping = Map.get(mappings_by_registry_id, registry.id)

      %{
        metric: registry.metric,
        human_readable_name: registry.human_readable_name,
        source_type: "registry",
        source_display: "Registry",
        source_id: registry.id,
        module: nil,
        mapping_id: mapping && mapping.id,
        category_id: mapping && mapping.category_id,
        category_name: mapping && mapping.category && mapping.category.name,
        group_id: mapping && mapping.group_id,
        group_name: mapping && mapping.group && mapping.group.name,
        categorized?: not is_nil(mapping)
      }
    end)
  end

  defp get_code_metrics(mappings_by_module_metric) do
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
      {:ok, human_readable_name} = Sanbase.Metric.human_readable_name(metric)

      %{
        metric: metric,
        human_readable_name: human_readable_name,
        source_type: "code",
        source_display: format_module_name(module),
        source_id: nil,
        module: module_str,
        mapping_id: mapping && mapping.id,
        category_id: mapping && mapping.category_id,
        category_name: mapping && mapping.category && mapping.category.name,
        group_id: mapping && mapping.group_id,
        group_name: mapping && mapping.group && mapping.group.name,
        categorized?: not is_nil(mapping)
      }
    end)
  end

  defp apply_filters(socket) do
    %{
      metrics: metrics,
      search_query: search_query,
      filter_source: filter_source,
      filter_status: filter_status,
      selected_category_id: selected_category_id
    } = socket.assigns

    filtered_metrics =
      metrics
      |> filter_by_search(search_query)
      |> filter_by_source(filter_source)
      |> filter_by_status(filter_status)
      |> filter_by_category(selected_category_id)
      |> Enum.sort_by(& &1.metric)

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
  defp filter_by_category(metrics, ""), do: metrics

  defp filter_by_category(metrics, category_id) when is_binary(category_id) do
    category_id = String.to_integer(category_id)
    Enum.filter(metrics, &(&1.category_id == category_id))
  end

  defp filter_by_category(metrics, category_id) when is_integer(category_id) do
    Enum.filter(metrics, &(&1.category_id == category_id))
  end

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
