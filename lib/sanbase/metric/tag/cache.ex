defmodule Sanbase.Metric.Tag.Cache do
  @moduledoc """
  Persistent-term-backed view of which concrete metric names carry each tag, and
  the inverse (metric name -> tag names).

  Registry-backed mappings are expanded through `Registry.resolve_safe/1`, so
  template parameters and aliases are covered automatically — tagging a single
  registry row transparently tags every concrete metric name it resolves to.
  Module/metric mappings are already concrete names.

  The computation fails closed: if the database is unavailable the maps resolve
  to empty, so a bundle plan temporarily sees zero tag-derived metrics rather
  than accidentally granting access.
  """

  require Logger

  alias Sanbase.Metric.Registry
  alias Sanbase.Metric.Tag.MetricTagMapping

  @doc """
  Returns the `MapSet` of concrete metric names carrying the given tag.
  """
  @spec metrics_for_tag(String.t()) :: MapSet.t()
  def metrics_for_tag(tag_name) when is_binary(tag_name) do
    Map.get(get(:tag_to_metrics_map), tag_name, MapSet.new())
  end

  @doc """
  Returns the `MapSet` union of concrete metric names carrying any of the given tags.
  """
  @spec metrics_for_tags([String.t()]) :: MapSet.t()
  def metrics_for_tags(tag_names) when is_list(tag_names) do
    Enum.reduce(tag_names, MapSet.new(), fn tag_name, acc ->
      MapSet.union(acc, metrics_for_tag(tag_name))
    end)
  end

  @doc """
  Returns the list of tag names attached to the given metric.
  """
  @spec tags_for_metric(String.t()) :: [String.t()]
  def tags_for_metric(metric) when is_binary(metric) do
    Map.get(get(:metric_to_tags_map), metric, [])
  end

  @doc """
  Recomputes the cached maps and stores them in `:persistent_term`.

  Both maps are derived from a single computation and published as one
  persistent-term value, so readers always observe a mutually consistent
  snapshot. Event-driven refreshes are serialized by the event bus subscriber
  process (`Sanbase.EventBus.MetricRegistrySubscriber`), which processes
  `metric_tag_change` events one at a time.
  """
  @spec refresh_stored_terms() :: true
  def refresh_stored_terms() do
    Logger.info("Refreshing stored terms in #{inspect(__MODULE__)}")

    tag_to_metrics_map = compute_tag_to_metrics_map()

    snapshot = %{
      tag_to_metrics_map: tag_to_metrics_map,
      metric_to_tags_map: invert_tag_to_metrics_map(tag_to_metrics_map)
    }

    :persistent_term.put(key(), snapshot)

    true
  end

  # Private

  defp key(), do: {__MODULE__, :snapshot}

  defp get(map_name) do
    case :persistent_term.get(key(), :undefined) do
      :undefined ->
        refresh_stored_terms()
        Map.fetch!(:persistent_term.get(key()), map_name)

      snapshot ->
        Map.fetch!(snapshot, map_name)
    end
  end

  defp compute_tag_to_metrics_map() do
    mappings = MetricTagMapping.list_all()
    resolved_names_by_registry_id = batch_resolve_registries(mappings)

    mappings
    |> Enum.group_by(& &1.tag.name)
    |> Map.new(fn {tag_name, mappings} ->
      metric_names =
        mappings
        |> Enum.flat_map(&mapping_metric_names(&1, resolved_names_by_registry_id))
        |> MapSet.new()

      {tag_name, metric_names}
    end)
  rescue
    e ->
      Logger.error(
        "[#{inspect(__MODULE__)}] Failed to compute tag_to_metrics_map: #{Exception.message(e)}"
      )

      %{}
  end

  defp invert_tag_to_metrics_map(tag_to_metrics_map) do
    tag_to_metrics_map
    |> Enum.flat_map(fn {tag_name, metric_names} ->
      Enum.map(metric_names, fn metric -> {metric, tag_name} end)
    end)
    |> Enum.group_by(fn {metric, _tag} -> metric end, fn {_metric, tag} -> tag end)
  end

  defp batch_resolve_registries(mappings) do
    registries =
      for %MetricTagMapping{metric_registry: %Registry{} = registry} <- mappings,
          uniq: true,
          do: registry

    {resolved, _errors} = Registry.resolve_safe(registries)

    Enum.group_by(resolved, & &1.id, & &1.metric)
  end

  defp mapping_metric_names(
         %MetricTagMapping{metric_registry: %Registry{} = registry},
         resolved_names_by_registry_id
       ) do
    Map.get(resolved_names_by_registry_id, registry.id, [])
  end

  defp mapping_metric_names(%MetricTagMapping{module: module, metric: metric}, _resolved)
       when is_binary(module) and is_binary(metric) do
    [metric]
  end

  defp mapping_metric_names(_, _resolved), do: []
end
