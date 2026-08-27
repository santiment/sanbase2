defmodule Sanbase.Metric.Catalog.Directory do
  @moduledoc """
  Public metrics directory: one row per exposed metric, enriched with the
  category/group taxonomy, and filterable/paginatable.

  This is the read model behind the public "metrics directory" listing - a
  searchable, category-faceted table of every metric the API exposes. It exists
  because the alternatives do not fit:

  - `getAvailableMetrics` returns names only, so a listing needs one
    `getMetric` call per row to render a human readable name, a cadence and a
    docs link;
  - `metric_display_order` (see `Sanbase.Metric.UIMetadata.DisplayOrder`) is the
    Sanbase chart sidebar taxonomy and covers only a subset of the metrics.

  The whole directory is built at once and cached in a `:persistent_term` with a
  TTL - it is read on every request and changes only when the registry or the
  taxonomy changes.
  """

  import Ecto.Query

  alias Sanbase.Cache.PersistentTermTtl
  alias Sanbase.Clickhouse.MetricAdapter.Registry, as: ClickhouseRegistry
  alias Sanbase.Metric.Category.MetricCategory
  alias Sanbase.Metric.Category.MetricCategoryMapping
  alias Sanbase.Repo

  @pt_key {__MODULE__, :entries}
  @ttl_ms :timer.minutes(10)

  @default_page_size 80
  @max_page_size 500

  @type entry :: %{
          metric: String.t(),
          human_readable_name: String.t() | nil,
          category_name: String.t() | nil,
          group_name: String.t() | nil,
          min_interval: String.t() | nil,
          docs: [%{link: String.t()}],
          is_deprecated: boolean(),
          status: String.t() | nil
        }

  @doc """
  Filtered and paginated metrics, plus the total number of metrics matching the
  filters - what a "showing X of Y" counter needs.

  Options:
  - `:search_term` - case insensitive substring matched against both the metric
    name and the human readable name;
  - `:categories` - keep only metrics in these categories (by name);
  - `:groups` - keep only metrics in these groups (by name);
  - `:include_deprecated` - include deprecated metrics. Defaults to false;
  - `:page`, `:page_size` - 1-based page and its size, capped at #{@max_page_size}.
  """
  @spec metrics(keyword()) :: %{total_count: non_neg_integer(), metrics: [entry()]}
  def metrics(opts \\ []) do
    matching = all_entries() |> filter(opts)

    page = opts |> Keyword.get(:page) |> normalize_page()
    page_size = opts |> Keyword.get(:page_size) |> normalize_page_size()

    %{
      total_count: length(matching),
      metrics: Enum.slice(matching, (page - 1) * page_size, page_size)
    }
  end

  @doc """
  All categories with their groups and the number of metrics in each. The counts
  come from the same entries `metrics/1` lists, so the per-category counts and
  the total are always consistent with the listing.

  Accepts the same `:search_term` and `:include_deprecated` options as
  `metrics/1`, so the facet counts can follow an active search.
  """
  @spec categories(keyword()) :: [map()]
  def categories(opts \\ []) do
    entries = all_entries() |> filter(Keyword.drop(opts, [:categories, :groups]))

    metrics_per_category = Enum.frequencies_by(entries, & &1.category_name)
    metrics_per_group = Enum.frequencies_by(entries, &{&1.category_name, &1.group_name})

    categories_with_groups()
    |> Enum.map(fn category ->
      %{
        name: category.name,
        short_description: category.short_description,
        description: category.description,
        display_order: category.display_order,
        metrics_count: Map.get(metrics_per_category, category.name, 0),
        groups:
          category.groups
          |> Enum.sort_by(&{&1.display_order || 0, &1.name})
          |> Enum.map(fn group ->
            %{
              name: group.name,
              short_description: group.short_description,
              display_order: group.display_order,
              metrics_count: Map.get(metrics_per_group, {category.name, group.name}, 0)
            }
          end)
      }
    end)
  end

  @doc """
  Drop the cached directory so the next read rebuilds it. Used after the
  registry or the taxonomy changes.
  """
  @spec expire_cache!() :: :ok
  def expire_cache!(), do: PersistentTermTtl.expire(@pt_key)

  # Private

  defp all_entries() do
    PersistentTermTtl.get_or_store(@pt_key, @ttl_ms, fn -> {:store, build_entries()} end)
  end

  defp build_entries() do
    categorization = categorization_map()

    human_readable_name_map = ClickhouseRegistry.human_readable_name_map()
    min_interval_map = ClickhouseRegistry.min_interval_map()
    docs_links_map = ClickhouseRegistry.docs_links_map()
    status_map = ClickhouseRegistry.name_to_status_map()

    Sanbase.Metric.available_metrics()
    |> Enum.sort()
    |> Enum.map(fn metric ->
      {category_name, group_name} = Map.get(categorization, metric, {nil, nil})

      %{
        metric: metric,
        human_readable_name:
          Map.get(human_readable_name_map, metric) || fallback_human_readable_name(metric),
        category_name: category_name,
        group_name: group_name,
        min_interval: Map.get(min_interval_map, metric) || fallback(metric, :min_interval),
        docs: metric |> docs_links(docs_links_map) |> Enum.map(&%{link: &1}),
        is_deprecated: deprecated?(metric),
        status: Map.get(status_map, metric)
      }
    end)
  end

  # A metric served by a module outside the registry (price, github, social,
  # ...) is not in the registry-backed maps, so its metadata is read through the
  # `Sanbase.Metric` facade instead.
  defp fallback_human_readable_name(metric) do
    case Sanbase.Metric.human_readable_name(metric) do
      {:ok, name} -> name
      _ -> nil
    end
  end

  defp fallback(metric, key) do
    case Sanbase.Metric.metadata(metric) do
      {:ok, metadata} -> Map.get(metadata, key)
      _ -> nil
    end
  end

  defp docs_links(metric, docs_links_map) do
    case Map.get(docs_links_map, metric) do
      [_ | _] = docs -> Enum.map(docs, & &1.link)
      _ -> metric |> fallback(:docs) |> List.wrap() |> Enum.map(& &1.link)
    end
  end

  defp deprecated?(metric) do
    hard_deprecate_after = Map.get(Sanbase.Metric.Helper.deprecated_metrics_map(), metric)

    is_struct(hard_deprecate_after, DateTime) or
      Map.get(Sanbase.Metric.Helper.soft_deprecated_metrics_map(), metric, false)
  end

  # metric name => {category name, group name}
  #
  # A mapping points either to a metric registry record - in which case all the
  # metrics that record resolves to (template expansions and aliases) inherit
  # the category - or directly to a module/metric pair for a code-defined
  # metric. A metric can be mapped more than once; the first mapping in taxonomy
  # display order wins, so a single badge is shown for it.
  defp categorization_map() do
    metrics_per_registry_id =
      ClickhouseRegistry.registry_id_map()
      |> Enum.group_by(fn {_metric, id} -> id end, fn {metric, _id} -> metric end)

    ordered_mappings()
    |> Enum.reduce(%{}, fn mapping, acc ->
      names = {mapping.category.name, mapping.group && mapping.group.name}

      mapping
      |> mapped_metrics(metrics_per_registry_id)
      |> Enum.reduce(acc, &Map.put_new(&2, &1, names))
    end)
  end

  defp mapped_metrics(%{metric_registry_id: id}, metrics_per_registry_id) when is_integer(id),
    do: Map.get(metrics_per_registry_id, id, [])

  defp mapped_metrics(%{metric: metric}, _metrics_per_registry_id) when is_binary(metric),
    do: [metric]

  defp mapped_metrics(_mapping, _metrics_per_registry_id), do: []

  defp ordered_mappings() do
    from(mapping in MetricCategoryMapping,
      join: category in assoc(mapping, :category),
      left_join: group in assoc(mapping, :group),
      order_by: [
        asc: category.display_order,
        asc: category.name,
        asc: group.display_order,
        asc: mapping.display_order,
        asc: mapping.id
      ],
      preload: [category: category, group: group]
    )
    |> Repo.all()
  end

  defp categories_with_groups() do
    from(category in MetricCategory,
      order_by: [asc: category.display_order, asc: category.name],
      preload: [:groups]
    )
    |> Repo.all()
  end

  defp filter(entries, opts) do
    entries
    |> filter_deprecated(Keyword.get(opts, :include_deprecated, false))
    |> filter_by(:category_name, Keyword.get(opts, :categories))
    |> filter_by(:group_name, Keyword.get(opts, :groups))
    |> filter_by_search_term(Keyword.get(opts, :search_term))
  end

  defp filter_deprecated(entries, true), do: entries
  defp filter_deprecated(entries, _), do: Enum.reject(entries, & &1.is_deprecated)

  defp filter_by(entries, _key, nil), do: entries
  defp filter_by(entries, _key, []), do: entries

  defp filter_by(entries, key, values) do
    values = MapSet.new(values)
    Enum.filter(entries, &MapSet.member?(values, Map.get(&1, key)))
  end

  defp filter_by_search_term(entries, nil), do: entries

  defp filter_by_search_term(entries, search_term) do
    case String.trim(search_term) do
      "" ->
        entries

      term ->
        term = String.downcase(term)

        Enum.filter(entries, fn entry ->
          String.contains?(String.downcase(entry.metric), term) or
            String.contains?(String.downcase(entry.human_readable_name || ""), term)
        end)
    end
  end

  defp normalize_page(page) when is_integer(page) and page > 0, do: page
  defp normalize_page(_page), do: 1

  defp normalize_page_size(size) when is_integer(size) and size > 0,
    do: min(size, @max_page_size)

  defp normalize_page_size(_size), do: @default_page_size
end
