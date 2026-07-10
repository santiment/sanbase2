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

  @functions [:tag_to_metrics_map, :metric_to_tags_map]

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
  Recomputes and stores all cached maps in `:persistent_term`.
  """
  @spec refresh_stored_terms() :: true
  def refresh_stored_terms() do
    Logger.info("Refreshing stored terms in #{inspect(__MODULE__)}")
    Enum.each(@functions, fn fun -> :persistent_term.put(key(fun), compute(fun)) end)
    true
  end

  # Private

  defp key(fun), do: {__MODULE__, fun}

  defp get(fun) do
    case :persistent_term.get(key(fun), :undefined) do
      :undefined ->
        data = compute(fun)
        :persistent_term.put(key(fun), data)
        data

      data ->
        data
    end
  end

  defp compute(:tag_to_metrics_map) do
    MetricTagMapping.list_all()
    |> Enum.group_by(& &1.tag.name)
    |> Map.new(fn {tag_name, mappings} ->
      metric_names =
        mappings
        |> Enum.flat_map(&resolve_mapping_metric_names/1)
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

  defp compute(:metric_to_tags_map) do
    get(:tag_to_metrics_map)
    |> Enum.flat_map(fn {tag_name, metric_names} ->
      Enum.map(metric_names, fn metric -> {metric, tag_name} end)
    end)
    |> Enum.group_by(fn {metric, _tag} -> metric end, fn {_metric, tag} -> tag end)
  end

  defp resolve_mapping_metric_names(%MetricTagMapping{metric_registry: %Registry{} = registry}) do
    {resolved, _errors} = Registry.resolve_safe([registry])
    Enum.map(resolved, & &1.metric)
  end

  defp resolve_mapping_metric_names(%MetricTagMapping{module: module, metric: metric})
       when is_binary(module) and is_binary(metric) do
    [metric]
  end

  defp resolve_mapping_metric_names(_), do: []
end
