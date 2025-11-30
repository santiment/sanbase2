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
  Pass `true` as the second argument to include metrics without UI metadata.
  """
  @spec get_ordered_metrics([MetricCategory.t()], boolean()) :: %{
          metrics: [map()],
          categories: [map()]
        }
  def get_ordered_metrics(categories \\ nil, include_without_ui_metadata \\ false) do
    # The returned metrics are taken from the mappings preloads in the categories.
    # Make sure to preload the necessary associations when calling this function.
    categories = categories || MetricCategory.list_ordered()
    categories = Enum.sort_by(categories, & &1.display_order, :asc)

    raise_if_no_preloads(categories)

    ordered_category_data = Enum.map(categories, fn cat -> %{id: cat.id, name: cat.name} end)

    # This map is used to enrich the output with registry metric data
    # It it is not used to generate the list of metrics.
    # The list of metrics
    registry_metrics = build_registry_map()

    metrics =
      categories
      |> Enum.flat_map(&flatten_category(&1, include_without_ui_metadata))
      |> Enum.map(&transform_to_output_format(&1, registry_metrics))

    %{metrics: metrics, categories: ordered_category_data}
  end

  defp raise_if_no_preloads(categories) do
    if Enum.any?(categories, fn cat -> not Ecto.assoc_loaded?(cat.mappings) end),
      do: raise("Mappings must be preloaded for all categories")

    if Enum.any?(categories, fn cat ->
         Enum.any?(cat.mappings, fn mapping ->
           not Ecto.assoc_loaded?(mapping.metric_registry) or
             not Ecto.assoc_loaded?(mapping.ui_metadata_list)
         end)
       end),
       do: raise("Groups must be preloaded for all categories")
  end

  defp flatten_category(category, include_without_ui_metadata) do
    ungrouped_metrics =
      flatten_mappings(category.mappings, category, _group = nil, include_without_ui_metadata)

    grouped_metrics =
      category.groups
      |> Enum.flat_map(fn group ->
        flatten_mappings(group.mappings, category, group, include_without_ui_metadata)
      end)

    ungrouped_metrics ++ grouped_metrics
  end

  defp flatten_mappings(mappings, category, group, include_without_ui_metadata) do
    mappings
    |> Enum.filter(&mapping_belongs_to_group?(&1, group))
    |> Enum.flat_map(&expand_mapping(&1, category, group, include_without_ui_metadata))
  end

  defp mapping_belongs_to_group?(mapping, _group = nil), do: is_nil(mapping.group_id)
  defp mapping_belongs_to_group?(mapping, group), do: mapping.group_id == group.id

  defp expand_mapping(mapping, category, group, include_without_ui_metadata) do
    cond do
      mapping.ui_metadata_list == [] and false == include_without_ui_metadata ->
        []

      mapping.ui_metadata_list == [] and true == include_without_ui_metadata ->
        [{mapping, nil, category, group}]

      true ->
        Enum.map(mapping.ui_metadata_list, fn ui_metadata ->
          {mapping, ui_metadata, category, group}
        end)
    end
  end

  defp transform_to_output_format({mapping, ui_metadata, category, group}, registry_metrics) do
    # Determine the metric name (not the human readable name) of the metric.
    # In case of mapping with ui_metadata, the metric name comes from it.
    # The mapping can be linked to a registry metric, or to a code metric.
    # In case of include_without_ui_metadata=true, there is no ui_metadata,
    # so the metric name comes from the mapping.
    # Such records without ui_metadata will be used only locally for tests
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

  defp get_ui_human_readable_name(ui_metadata, metric_name) do
    if ui_metadata && ui_metadata.ui_human_readable_name do
      ui_metadata.ui_human_readable_name
    else
      with {:ok, human_readable_name} <- Sanbase.Metric.human_readable_name(metric_name) do
        human_readable_name
      else
        _ -> metric_name
      end
    end
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
