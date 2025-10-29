defmodule Sanbase.Metric.Category.DisplayOrder do
  @moduledoc """
  Module for building ordered lists of metrics based on the category system.

  This module is responsible for flattening the hierarchical category/group/mapping
  structure into an ordered flat list of metrics, matching the output format of
  the legacy DisplayOrder system.
  """

  alias Sanbase.Metric.Registry
  alias Sanbase.Metric.Category.MetricCategory

  @doc """
  Builds an ordered list of all metrics with their metadata.

  Returns the same shape as DisplayOrder.get_ordered_metrics for compatibility.
  The ordering follows: category order → ungrouped mappings → groups (by order) →
  mappings within groups → ui_metadata within mappings.
  """
  @spec get_ordered_metrics([MetricCategory.t()]) :: %{metrics: [map()], categories: [map()]}
  def get_ordered_metrics(categories) do
    ordered_category_data = Enum.map(categories, fn cat -> %{id: cat.id, name: cat.name} end)

    registry_metrics = build_registry_map()

    metrics =
      categories
      |> Enum.flat_map(&flatten_category/1)
      |> Enum.map(&transform_to_output_format(&1, registry_metrics))

    %{
      metrics: metrics,
      categories: ordered_category_data
    }
  end

  defp flatten_category(category) do
    ungrouped_metrics = flatten_mappings(category.mappings, category, nil)

    grouped_metrics =
      category.groups
      |> Enum.flat_map(fn group ->
        flatten_mappings(group.mappings, category, group)
      end)

    ungrouped_metrics ++ grouped_metrics
  end

  defp flatten_mappings(mappings, category, group) do
    mappings
    |> Enum.filter(&mapping_belongs_to_group?(&1, group))
    |> Enum.flat_map(&expand_mapping_with_ui_metadata(&1, category, group))
  end

  defp mapping_belongs_to_group?(mapping, nil), do: is_nil(mapping.group_id)
  defp mapping_belongs_to_group?(mapping, group), do: mapping.group_id == group.id

  defp expand_mapping_with_ui_metadata(mapping, category, group) do
    if mapping.ui_metadata_list == [] do
      [{mapping, nil, category, group}]
    else
      Enum.map(mapping.ui_metadata_list, fn ui_metadata ->
        {mapping, ui_metadata, category, group}
      end)
    end
  end

  defp transform_to_output_format({mapping, ui_metadata, category, group}, registry_metrics) do
    metric_name = determine_metric_name(mapping, ui_metadata)
    registry_metric = Map.get(registry_metrics, metric_name)

    Map.merge(
      build_base_metric_info(mapping, ui_metadata, metric_name, registry_metric),
      build_category_group_info(category, group, mapping, ui_metadata)
    )
  end

  defp build_base_metric_info(mapping, ui_metadata, metric_name, registry_metric) do
    source_type = determine_source_type(mapping)
    code_module = determine_code_module(mapping)
    inserted_at = ui_metadata_or_mapping_field(ui_metadata, mapping, :inserted_at)

    %{
      id: ui_metadata_or_mapping_field(ui_metadata, mapping, :id),
      metric: metric_name,
      registry_metric: registry_metric,
      ui_human_readable_name: get_ui_human_readable_name(ui_metadata, metric_name),
      ui_key: ui_metadata_or_default(ui_metadata, :ui_key, nil),
      chart_style: ui_metadata_or_default(ui_metadata, :chart_style, "line"),
      unit: ui_metadata_or_default(ui_metadata, :unit, ""),
      description: "",
      source_type: source_type,
      code_module: code_module,
      metric_registry_id: mapping.metric_registry_id,
      args: ui_metadata_or_default(ui_metadata, :args, %{}),
      is_new: new?(inserted_at),
      display_order: mapping.display_order,
      inserted_at: inserted_at,
      updated_at: ui_metadata_or_mapping_field(ui_metadata, mapping, :updated_at),
      type: "metric"
    }
  end

  defp build_category_group_info(category, group, _mapping, _ui_metadata) do
    %{
      category_id: category.id,
      category_name: category.name,
      group_id: if(group, do: group.id, else: nil),
      group_name: if(group, do: group.name, else: nil)
    }
  end

  defp get_ui_human_readable_name(nil, metric_name), do: metric_name

  defp get_ui_human_readable_name(ui_metadata, metric_name) do
    ui_metadata.ui_human_readable_name || metric_name
  end

  defp ui_metadata_or_mapping_field(nil, mapping, field), do: Map.get(mapping, field)
  defp ui_metadata_or_mapping_field(ui_metadata, _mapping, field), do: Map.get(ui_metadata, field)

  defp ui_metadata_or_default(nil, _field, default), do: default

  defp ui_metadata_or_default(ui_metadata, field, default) do
    Map.get(ui_metadata, field) || default
  end

  defp determine_metric_name(mapping, ui_metadata) do
    cond do
      ui_metadata && ui_metadata.metric -> ui_metadata.metric
      mapping.metric_registry && mapping.metric_registry.metric -> mapping.metric_registry.metric
      mapping.metric -> mapping.metric
      true -> "unknown"
    end
  end

  defp determine_source_type(mapping) do
    if mapping.metric_registry_id, do: "registry", else: "code"
  end

  defp determine_code_module(mapping) do
    cond do
      mapping.module -> mapping.module
      mapping.metric_registry_id -> nil
      true -> nil
    end
  end

  defp build_registry_map do
    Registry.all()
    |> Registry.resolve()
    |> Enum.reduce(%{}, fn registry, acc ->
      Map.put(acc, registry.metric, registry)
    end)
  end

  defp new?(inserted_at, days \\ 14) do
    case inserted_at do
      nil ->
        false

      date ->
        threshold = DateTime.utc_now() |> DateTime.add(-days * 24 * 60 * 60, :second)

        date_with_timezone =
          case date do
            %NaiveDateTime{} ->
              DateTime.from_naive!(date, "Etc/UTC")

            %DateTime{} ->
              date
          end

        DateTime.compare(date_with_timezone, threshold) == :gt
    end
  end
end
