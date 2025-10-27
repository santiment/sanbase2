defmodule Sanbase.Metric.Category.Scripts.CopyUIMetadata do
  alias Sanbase.Metric.UIMetadata.DisplayOrder
  alias Sanbase.Metric.Category

  def run() do
    available_metrics = Sanbase.Metric.available_metrics()

    metric_to_registry_id_map =
      Sanbase.Metric.Registry.all()
      |> Sanbase.Metric.Registry.resolve()
      |> Map.new(&{&1.metric, &1.id})

    DisplayOrder.get_ordered_metrics()
    |> Map.fetch!(:metrics)
    |> Enum.each(fn m ->
      # In some case like price_volatility_1w, the metric is wrongly not linked to the registry, but it should be.
      # With this Map.put we put the true registry_id, if it exists, so we'll enter the correct clause in the next function
      # which checks not only if metric_registry_id is present, but also if it's an integer
      m = Map.put(m, :metric_registry_id, Map.get(metric_to_registry_id_map, m.metric))
      import_ui_metric_metadata(m, available_metrics)
    end)
  end

  defp import_ui_metric_metadata(
         %{metric_registry_id: metric_registry_id} = map,
         available_metrics
       )
       when is_integer(metric_registry_id) do
    with {:ok, mapping} <- Category.get_mapping_by_metric_registry_id(metric_registry_id) do
      metric = Map.fetch!(map, :metric) |> maybe_fix_metric_name(available_metrics)

      params =
        Map.take(map, [:args, :ui_key, :ui_human_readable_name, :unit, :chart_style])
        |> Map.merge(%{
          metric: metric,
          display_order_in_mapping: 1,
          metric_category_mapping_id: mapping.id
        })

      case Category.create_ui_metadata(params) do
        {:ok, _} ->
          :ok

        {:error, changeset} ->
          IO.puts("""
          Failed to copy UI metadata for metric registry id #{metric_registry_id}
          Reason: #{Sanbase.Utils.ErrorHandling.changeset_errors_string(changeset)}
          """)
      end
    end
  end

  defp import_ui_metric_metadata(%{code_module: module, metric: metric} = map, _available_metrics)
       when is_binary(metric) do
    module = module || "__none__"

    with {:ok, mapping} <- Category.get_mapping_by_module_and_metric(module, metric) do
      params =
        Map.take(map, [:metric, :args, :ui_key, :ui_human_readable_name, :unit, :chart_style])
        |> Map.merge(%{
          metric: metric,
          display_order_in_mapping: 1,
          metric_category_mapping_id: mapping.id
        })

      case Category.create_ui_metadata(params) do
        {:ok, _} ->
          :ok

        {:error, changeset} ->
          IO.puts("""
          Failed to copy UI metadata for module/metric #{module}/#{metric}
          Reason: #{Sanbase.Utils.ErrorHandling.changeset_errors_string(changeset)}
          """)
      end
    end
  end

  defp maybe_fix_metric_name(metric, available_metrics) do
    closest_metric = Enum.max_by(available_metrics, fn m -> String.jaro_distance(metric, m) end)

    if metric != closest_metric do
      IO.puts("""
      Metric from DisplayOrder #{metric} is likely mistyped or no longer supported.
      The closest metric to it is: #{closest_metric} with jaro distance: #{String.jaro_distance(metric, closest_metric)}
      """)
    end

    closest_metric
  end
end
