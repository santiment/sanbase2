defmodule Sanbase.Metric.Catalog do
  @moduledoc """
  Builds a unified "one row per metric" listing of all metrics in the system:

  - Metric Registry rows (`Sanbase.Metric.Registry`). Parametrized (template)
    metrics are represented as a single entry whose `variants_count` is the
    number of parameter expansions;
  - Code-defined metrics coming from adapter modules outside the registry
    (price, github, social, etc.), deduplicated against the resolved registry
    metric names so a metric served by the registry is never listed twice.

  Used by the admin dashboards (categorization, tagging) which annotate the
  entries with their own domain data. Entries are plain maps with no UI or
  persistence coupling:

      %{
        metric: "price_usd",
        human_readable_name: "Price in USD",
        source_type: "code",                      # or "registry"
        source_display: "MetricAdapter",          # or "Registry"
        source_id: nil,                           # or the metric_registry id
        module: "Sanbase.Price.MetricAdapter",    # nil for registry entries
        parameters_count: 0,
        variants_count: 1
      }
  """

  alias Sanbase.Metric.Helper
  alias Sanbase.Metric.Registry

  @doc """
  Return one entry per metric, sorted by metric name.
  """
  @spec all_metrics() :: [map()]
  def all_metrics() do
    registry_rows = Registry.all()

    (registry_entries(registry_rows) ++ code_entries(registry_rows))
    |> Enum.sort_by(& &1.metric, :asc)
  end

  @doc """
  Canonical identity of a metric across the registry-vs-code duality.

  Accepts either a catalog entry (`source_type`/`source_id`/`module`/`metric`)
  or a mapping-style map/struct carrying `metric_registry_id` or
  `module` + `metric` (e.g. `MetricTagMapping`, `MetricCategoryMapping`).
  Both shapes produce the same key, so mapping rows can be joined to catalog
  entries without each consumer restating the dispatch.
  """
  @spec entry_key(map() | struct()) :: tuple()
  def entry_key(%{source_type: "registry", source_id: id}), do: {"registry", id}

  def entry_key(%{source_type: "code", module: module, metric: metric}),
    do: {"code", module, metric}

  def entry_key(%{metric_registry_id: id}) when is_integer(id), do: {"registry", id}

  def entry_key(%{module: module, metric: metric})
      when is_binary(module) and is_binary(metric),
      do: {"code", module, metric}

  @doc """
  Index mapping rows by their `entry_key/1` for `mappings_for_entry/2` lookups.
  """
  @spec index_mappings([map() | struct()]) :: map()
  def index_mappings(mappings), do: Enum.group_by(mappings, &entry_key/1)

  @doc """
  All mapping rows belonging to the given catalog entry.
  """
  @spec mappings_for_entry(map(), map()) :: [map() | struct()]
  def mappings_for_entry(entry, mappings_index),
    do: Map.get(mappings_index, entry_key(entry), [])

  defp registry_entries(registry_rows) do
    Enum.map(registry_rows, fn registry ->
      %{
        metric: registry.metric,
        human_readable_name: registry.human_readable_name,
        source_type: "registry",
        source_display: "Registry",
        source_id: registry.id,
        module: nil,
        parameters_count: length(registry.parameters),
        variants_count: max(1, length(registry.parameters))
      }
    end)
  end

  defp code_entries(registry_rows) do
    registry_metrics_mapset =
      registry_rows
      |> Registry.resolve()
      |> Enum.map(& &1.metric)
      |> MapSet.new()

    Helper.metric_to_module_map()
    |> Enum.reject(fn {metric, _module} -> metric in registry_metrics_mapset end)
    |> Enum.map(fn {metric, module} ->
      {:ok, human_readable_name} = Sanbase.Metric.human_readable_name(metric)

      %{
        metric: metric,
        human_readable_name: human_readable_name,
        source_type: "code",
        source_display: format_module_name(module),
        source_id: nil,
        module: inspect(module),
        parameters_count: 0,
        variants_count: 1
      }
    end)
  end

  defp format_module_name(module) do
    module
    |> inspect()
    |> String.split(".")
    |> List.last()
  end
end
