defmodule SanbaseWeb.TagLive.Index do
  use SanbaseWeb, :live_view

  alias Sanbase.Metric.Tag
  alias Sanbase.Metric.Registry
  alias Sanbase.Metric.Helper
  alias SanbaseWeb.AdminSharedComponents

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Metric Tagging",
       metrics: [],
       filtered_metrics: [],
       tags: [],
       search_query: "",
       filter_source: "all",
       filter_status: "all",
       filter_tag: "all",
       loading: true
     )
     |> load_data()}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply,
     socket
     |> assign(
       search_query: params["search"] || "",
       filter_source: params["source"] || "all",
       filter_status: params["status"] || "all",
       filter_tag: params["tag"] || "all"
     )
     |> apply_filters()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col justify-center w-full">
      <div class="text-2xl mb-4">
        Metric Tagging
      </div>

      <.navigation />

      <div class="text-base-content/70 whitespace-pre-line" phx-no-curly-interpolation>
        Attach tags (labels) to metrics. Tags are used, among other things, to expose a curated subset of metrics on bundle subscription plans.
        A metric can carry multiple tags. Parametrized metrics like `mvrv_usd_{{timebound}}` are shown as a single row; a tag applies to all their variants.
      </div>

      <.filters
        search_query={@search_query}
        filter_source={@filter_source}
        filter_status={@filter_status}
        filter_tag={@filter_tag}
        tags={@tags}
      />

      <.metrics_stats metrics={@metrics} filtered_metrics={@filtered_metrics} />

      <.metrics_table :if={!@loading} filtered_metrics={@filtered_metrics} tags={@tags} />

      <div :if={@loading} class="flex justify-center items-center py-12">
        <span class="loading loading-spinner loading-lg text-primary"></span>
        <p class="ml-4 text-base-content/70">Loading metrics...</p>
      </div>
    </div>
    """
  end

  def navigation(assigns) do
    ~H"""
    <div class="my-4 flex flex-row space-x-2">
      <AdminSharedComponents.nav_button
        text="Back to Metric Registry"
        href={~p"/admin/metric_registry"}
        icon="hero-home"
      />
      <AdminSharedComponents.nav_button
        text="Manage Tags"
        href={~p"/admin/metric_registry/tags/manage"}
        icon="hero-tag"
      />
    </div>
    """
  end

  attr :search_query, :string, required: true
  attr :filter_source, :string, required: true
  attr :filter_status, :string, required: true
  attr :filter_tag, :string, required: true
  attr :tags, :list, required: true

  def filters(assigns) do
    ~H"""
    <div class="card bg-base-100 border border-base-300 shadow p-4 my-4">
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
              {"Tagged", "tagged"},
              {"Not Tagged", "not_tagged"}
            ]}
          />

          <.input
            type="select"
            name="tag"
            value={@filter_tag}
            label="Tag"
            options={[
              {"All Tags", "all"},
              {"Not Tagged", "none"}
              | Enum.map(@tags, fn t -> {t.name, t.id} end)
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

    tagged_count = Enum.count(assigns.filtered_metrics, & &1.tagged?)
    not_tagged_count = filtered_count - tagged_count

    assigns =
      assign(assigns,
        metrics_count: metrics_count,
        variants_count: variants_count,
        filtered_count: filtered_count,
        filtered_variants_count: filtered_variants_count,
        tagged_count: tagged_count,
        not_tagged_count: not_tagged_count
      )

    ~H"""
    <div class="flex flex-row flex-wrap gap-4 my-2">
      <.stat label="Metrics (filtered / total)" value={"#{@filtered_count} / #{@metrics_count}"} />
      <.stat
        label="Variants (filtered / total)"
        value={"#{@filtered_variants_count} / #{@variants_count}"}
      />
      <.stat label="Tagged" value={@tagged_count} />
      <.stat label="Not tagged" value={@not_tagged_count} />
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true

  def stat(assigns) do
    ~H"""
    <div class="rounded-box border border-base-300 px-4 py-2">
      <div class="text-xs text-base-content/60">{@label}</div>
      <div class="text-lg font-semibold">{@value}</div>
    </div>
    """
  end

  attr :filtered_metrics, :list, required: true
  attr :tags, :list, required: true

  def metrics_table(assigns) do
    ~H"""
    <div class="rounded-box border border-base-300 overflow-hidden">
      <div class="overflow-x-auto">
        <table class="table table-sm">
          <thead>
            <tr>
              <th>Metric</th>
              <th>Source</th>
              <th>Tags</th>
              <th>Add tag</th>
            </tr>
          </thead>
          <tbody>
            <.metric_row :for={metric <- @filtered_metrics} metric={metric} tags={@tags} />
          </tbody>
        </table>
      </div>

      <div :if={@filtered_metrics == []} class="px-6 py-12 text-center text-base-content/50">
        No metrics found matching your filters.
      </div>
    </div>
    """
  end

  attr :metric, :map, required: true
  attr :tags, :list, required: true

  def metric_row(assigns) do
    assigned_tag_ids = MapSet.new(assigns.metric.tags, & &1.tag_id)
    available_tags = Enum.reject(assigns.tags, &MapSet.member?(assigned_tag_ids, &1.id))
    assigns = assign(assigns, available_tags: available_tags)

    ~H"""
    <tr class="hover:bg-base-200">
      <td class="max-w-[360px] break-words">
        <div class="flex flex-col">
          <div class="text-sm font-medium">{@metric.metric}</div>
          <div class="text-xs text-base-content/60">{@metric.human_readable_name}</div>
          <div :if={@metric.variants_count >= 2} class="text-xs text-secondary">
            ({@metric.variants_count} variants)
          </div>
        </div>
      </td>
      <td>
        <span :if={@metric.source_type == "registry"} class="badge badge-sm badge-info badge-soft">
          <.link navigate={~p"/admin/metric_registry/show/#{@metric.source_id}"}>
            {@metric.source_display}
          </.link>
        </span>
        <span :if={@metric.source_type == "code"} class="badge badge-sm badge-secondary badge-soft">
          {@metric.source_display}
        </span>
      </td>
      <td class="max-w-[320px]">
        <div :if={@metric.tags == []} class="text-sm text-base-content/40 italic">
          Not tagged
        </div>
        <div class="flex flex-wrap gap-1">
          <span
            :for={tag <- @metric.tags}
            class="badge badge-sm badge-primary badge-soft gap-1"
          >
            {tag.tag_name}
            <button
              phx-click="remove_tag"
              phx-value-mapping_id={tag.mapping_id}
              class="hover:text-error"
              data-confirm={"Remove tag '#{tag.tag_name}' from #{@metric.metric}?"}
              aria-label="Remove tag"
            >
              <.icon name="hero-x-mark" class="size-3" />
            </button>
          </span>
        </div>
      </td>
      <td>
        <div class="flex flex-wrap gap-1">
          <button
            :for={tag <- @available_tags}
            phx-click="add_tag"
            phx-value-tag_id={tag.id}
            phx-value-registry_id={@metric.source_id}
            phx-value-module={@metric.module}
            phx-value-metric={@metric.metric}
            class="badge badge-sm badge-ghost hover:badge-primary hover:badge-soft"
          >
            + {tag.name}
          </button>
          <span :if={@available_tags == []} class="text-xs text-base-content/40 italic">
            All tags assigned
          </span>
        </div>
      </td>
    </tr>
    """
  end

  @impl true
  def handle_event("filter", params, socket) do
    query_params =
      %{}
      |> maybe_add_param("search", params["search"] || "")
      |> maybe_add_param("source", params["source"] || "all", "all")
      |> maybe_add_param("status", params["status"] || "all", "all")
      |> maybe_add_param("tag", params["tag"] || "all", "all")

    {:noreply, push_patch(socket, to: ~p"/admin/metric_registry/tags?#{query_params}")}
  end

  def handle_event("add_tag", params, socket) do
    %{"tag_id" => tag_id} = params
    tag_id = String.to_integer(tag_id)

    attrs =
      case params["registry_id"] do
        registry_id when is_binary(registry_id) and registry_id != "" ->
          %{tag_id: tag_id, metric_registry_id: String.to_integer(registry_id)}

        _ ->
          %{tag_id: tag_id, module: params["module"], metric: params["metric"]}
      end

    case Tag.create_mapping(attrs) do
      {:ok, _} ->
        {:noreply, socket |> load_data() |> apply_filters()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to add tag (it may already be assigned)")}
    end
  end

  def handle_event("remove_tag", %{"mapping_id" => id}, socket) do
    id = String.to_integer(id)

    case Tag.get_mapping(id) do
      {:ok, mapping} ->
        Tag.delete_mapping(mapping)
        {:noreply, socket |> load_data() |> apply_filters()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Mapping not found")}
    end
  end

  defp load_data(socket) do
    tags = Tag.list_tags()
    mappings = Tag.list_all_mappings()

    mappings_by_registry_id =
      mappings
      |> Enum.filter(& &1.metric_registry_id)
      |> Enum.group_by(& &1.metric_registry_id)

    mappings_by_module_metric =
      mappings
      |> Enum.filter(&(&1.module && &1.metric))
      |> Enum.group_by(&{&1.module, &1.metric})

    registry_metrics = get_registry_metrics(mappings_by_registry_id)
    code_metrics = get_code_metrics(mappings_by_module_metric)

    all_metrics = Enum.sort_by(registry_metrics ++ code_metrics, & &1.metric, :asc)

    assign(socket, metrics: all_metrics, tags: tags, loading: false)
  end

  defp get_registry_metrics(mappings_by_registry_id) do
    Registry.all()
    |> Enum.map(fn registry ->
      mappings = Map.get(mappings_by_registry_id, registry.id, [])

      %{
        metric: registry.metric,
        human_readable_name: registry.human_readable_name,
        source_type: "registry",
        source_display: "Registry",
        source_id: registry.id,
        module: nil,
        tags: mappings_to_tags(mappings),
        tagged?: mappings != [],
        variants_count: max(1, length(registry.parameters))
      }
    end)
  end

  defp get_code_metrics(mappings_by_module_metric) do
    registry_metrics_mapset =
      Registry.all()
      |> Registry.resolve()
      |> Enum.map(& &1.metric)
      |> MapSet.new()

    Helper.metric_to_module_map()
    |> Enum.reject(fn {metric, _module} -> metric in registry_metrics_mapset end)
    |> Enum.map(fn {metric, module} ->
      module_str = inspect(module)
      mappings = Map.get(mappings_by_module_metric, {module_str, metric}, [])
      {:ok, human_readable_name} = Sanbase.Metric.human_readable_name(metric)

      %{
        metric: metric,
        human_readable_name: human_readable_name,
        source_type: "code",
        source_display: format_module_name(module),
        source_id: nil,
        module: module_str,
        tags: mappings_to_tags(mappings),
        tagged?: mappings != [],
        variants_count: 1
      }
    end)
  end

  defp mappings_to_tags(mappings) do
    mappings
    |> Enum.map(fn mapping ->
      %{tag_id: mapping.tag_id, tag_name: mapping.tag.name, mapping_id: mapping.id}
    end)
    |> Enum.sort_by(& &1.tag_name)
  end

  defp apply_filters(socket) do
    %{
      metrics: metrics,
      search_query: search_query,
      filter_source: filter_source,
      filter_status: filter_status,
      filter_tag: filter_tag
    } = socket.assigns

    filtered_metrics =
      metrics
      |> filter_by_search(search_query)
      |> filter_by_source(filter_source)
      |> filter_by_status(filter_status)
      |> filter_by_tag(filter_tag)

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
  defp filter_by_status(metrics, "tagged"), do: Enum.filter(metrics, & &1.tagged?)
  defp filter_by_status(metrics, "not_tagged"), do: Enum.filter(metrics, &(not &1.tagged?))

  defp filter_by_tag(metrics, "all"), do: metrics
  defp filter_by_tag(metrics, "none"), do: Enum.filter(metrics, &(&1.tags == []))

  defp filter_by_tag(metrics, tag_id) when is_binary(tag_id) do
    tag_id = String.to_integer(tag_id)
    Enum.filter(metrics, fn m -> Enum.any?(m.tags, &(&1.tag_id == tag_id)) end)
  end

  defp format_module_name(module) do
    module
    |> inspect()
    |> String.split(".")
    |> List.last()
  end

  defp maybe_add_param(params, _key, ""), do: params
  defp maybe_add_param(params, key, value), do: Map.put(params, key, value)

  defp maybe_add_param(params, _key, value, default) when value == default, do: params
  defp maybe_add_param(params, key, value, _default), do: Map.put(params, key, value)
end
