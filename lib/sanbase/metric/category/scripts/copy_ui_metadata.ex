defmodule Sanbase.Metric.Category.Scripts.CopyUIMetadata do
  alias Sanbase.Metric.UIMetadata.DisplayOrder
  alias Sanbase.Metric.Category

  def run() do
    DisplayOrder.get_ordered_metrics()
    |> Map.fetch!(:metrics)
    |> Enum.each(fn m ->
      import_ui_metric_metadata(m)
    end)
  end

  defp import_ui_metric_metadata(%{metric_registry_id: metric_registry_id} = map)
       when is_integer(metric_registry_id) do
    with {:ok, mapping} <- Category.get_mapping_by_metric_registry_id(metric_registry_id) do
      params =
        Map.take(map, [:args, :ui_key, :ui_human_readable_name, :unit, :chart_style])
        |> Map.merge(%{
          display_order_in_mapping: 1,
          metric_category_mapping_id: mapping.id
        })

      Category.create_ui_metadata(params)
    end
  end

  defp import_ui_metric_metadata(%{code_module: module, metric: metric} = map)
       when is_binary(metric) do
    module = module || "__none__"

    with {:ok, mapping} <- Category.get_mapping_by_module_and_metric(module, metric) do
      params =
        Map.take(map, [:args, :ui_key, :ui_human_readable_name, :unit, :chart_style])
        |> Map.merge(%{
          display_order_in_mapping: 1,
          metric_category_mapping_id: mapping.id
        })

      Category.create_ui_metadata(params)
    end
  end
end
